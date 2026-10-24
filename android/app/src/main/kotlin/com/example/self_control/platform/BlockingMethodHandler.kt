package com.example.self_control.platform

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.example.self_control.apps.InstalledAppProvider
import com.example.self_control.blocking.BlockingCapability
import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.ScheduleRule
import com.example.self_control.persistence.SharedPreferencesBlockingStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class BlockingMethodHandler(
    private val context: Context,
    private val appProvider: InstalledAppProvider = InstalledAppProvider(context),
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
) : MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBlockingCapability" -> handleGetBlockingCapability(result)
            "getAccessibilityStatus" -> handleGetAccessibilityStatus(result)
            "isAccessibilityServiceEnabled" -> handleIsAccessibilityServiceEnabled(result)
            "openAccessibilitySettings" -> handleOpenAccessibilitySettings(result)
            "isIgnoringBatteryOptimizations" -> handleIsIgnoringBatteryOptimizations(result)
            "requestIgnoreBatteryOptimizations" -> handleRequestIgnoreBatteryOptimizations(result)
            "getInstalledApps" -> handleGetInstalledApps(result)
            "syncBlockedApps" -> handleSyncBlockedApps(call, result)
            "syncTemporaryUnlock" -> handleSyncTemporaryUnlock(call, result)
            "revokeTemporaryUnlock" -> handleRevokeTemporaryUnlock(call, result)
            "syncActiveSessions" -> handleSyncActiveSessions(call, result)
            "consumePendingBootEvents", "getPendingBootSyncs" -> handleConsumePendingBootEvents(result)
            "consumePendingActivityLogs" -> handleConsumePendingActivityLogs(result)
            "getCurrentBlockingState" -> handleGetCurrentBlockingState(result)
            "getLastBlockingResult" -> handleGetLastBlockingResult(result)
            else -> result.notImplemented()
        }
    }

    private fun handleGetBlockingCapability(result: MethodChannel.Result) {
        try {
            val capability = BlockingCapability.detect(context)
            result.success(capability.toMap())
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "mode" to "accessibility",
                    "serviceStatus" to "disabled",
                    "limitations" to emptyList<String>()
                )
            )
        }
    }

    private fun handleGetAccessibilityStatus(result: MethodChannel.Result) {
        try {
            val isEnabled = BlockingCapability.isAccessibilityServiceEnabled(context)
            result.success(if (isEnabled) "enabled" else "disabled")
        } catch (e: Exception) {
            result.success("disabled")
        }
    }

    private fun handleOpenAccessibilitySettings(result: MethodChannel.Result) {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleGetInstalledApps(result: MethodChannel.Result) {
        executor.execute {
            try {
                val apps = appProvider.getInstalledApps()
                mainHandler.post {
                    result.success(apps)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.success(emptyList<Map<String, Any?>>())
                }
            }
        }
    }

    private fun handleSyncBlockedApps(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packages: List<String> = when (val args = call.arguments) {
                is Map<*, *> -> (args["packages"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
                is List<*> -> args.filterIsInstance<String>()
                else -> emptyList()
            }

            BlockingEngine.instance.syncBlockedApps(packages)
            val store = SharedPreferencesBlockingStore.create(context)
            store.saveBlockedPackages(packages)

            result.success(
                mapOf(
                    "syncedCount" to packages.size,
                    "status" to "success"
                )
            )
        } catch (e: Exception) {
            result.error("SYNC_FAILED", e.message, null)
        }
    }

    private fun handleSyncTemporaryUnlock(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("packageName")
                ?: return result.error("INVALID_ARGUMENT", "packageName is required", null)
            val durationSeconds = call.argument<Int>("durationSeconds") ?: 0
            val expiresAtEpochMs = call.argument<Number>("expiresAtEpochMs")?.toLong()

            val expiration = BlockingEngine.instance.registerTemporaryUnlock(
                packageName = packageName,
                durationSeconds = durationSeconds,
                expiresAtEpochMs = expiresAtEpochMs
            )

            val store = SharedPreferencesBlockingStore.create(context)
            store.saveTemporaryUnlock(packageName, expiration)

            result.success(
                mapOf(
                    "status" to "success",
                    "packageName" to packageName,
                    "expiresAtEpochMs" to expiration
                )
            )
        } catch (e: Exception) {
            result.error("SYNC_UNLOCK_FAILED", e.message, null)
        }
    }

    private fun handleRevokeTemporaryUnlock(call: MethodCall, result: MethodChannel.Result) {
        try {
            val packageName = call.argument<String>("packageName") ?: ""
            BlockingEngine.instance.revokeTemporaryUnlock(packageName)
            val store = SharedPreferencesBlockingStore.create(context)
            store.removeTemporaryUnlock(packageName)
            result.success(mapOf("status" to "success", "packageName" to packageName))
        } catch (e: Exception) {
            result.error("REVOKE_UNLOCK_FAILED", e.message, null)
        }
    }

    private fun handleSyncActiveSessions(call: MethodCall, result: MethodChannel.Result) {
        try {
            val isStrict = call.argument<Boolean>("isStrictSessionActive") ?: false
            val sessionEnd = call.argument<Number>("sessionEndEpochMs")?.toLong()
            val schedMap = call.argument<Map<String, Any?>>("activeSchedule")

            val scheduleRule = if (schedMap != null) {
                val startMinute = (schedMap["scheduleStartMinute"] as? Number)?.toInt() ?: 0
                val endMinute = (schedMap["scheduleEndMinute"] as? Number)?.toInt() ?: 0
                val daysMask = (schedMap["daysMask"] as? Number)?.toInt() ?: 127
                val isEnabled = schedMap["isEnabled"] as? Boolean ?: true
                ScheduleRule(
                    startMinute = startMinute,
                    endMinute = endMinute,
                    daysMask = daysMask,
                    isEnabled = isEnabled
                )
            } else {
                null
            }

            BlockingEngine.instance.syncActiveSessions(isStrict, sessionEnd, scheduleRule)
            val store = SharedPreferencesBlockingStore.create(context)
            if (sessionEnd != null && isStrict) {
                val start = System.currentTimeMillis()
                store.saveActiveSession(start, sessionEnd, "active")
            } else {
                store.updateSessionStatus("completed")
            }

            result.success(mapOf("status" to "success"))
        } catch (e: Exception) {
            result.error("SYNC_SESSION_FAILED", e.message, null)
        }
    }

    private fun handleConsumePendingBootEvents(result: MethodChannel.Result) {
        try {
            val store = SharedPreferencesBlockingStore.create(context)
            val pendingTimestamps = store.consumePendingBootSyncs()
            result.success(pendingTimestamps)
        } catch (e: Exception) {
            result.success(emptyList<Long>())
        }
    }

    private fun handleGetCurrentBlockingState(result: MethodChannel.Result) {
        try {
            val engine = BlockingEngine.instance
            result.success(
                mapOf(
                    "isBlockingActive" to engine.isBlockingActive,
                    "activePackage" to engine.activePackage,
                    "blockedCount" to engine.blockedCount
                )
            )
        } catch (e: Exception) {
            result.success(
                mapOf(
                    "isBlockingActive" to false,
                    "activePackage" to null,
                    "blockedCount" to 0
                )
            )
        }
    }

    private fun handleGetLastBlockingResult(result: MethodChannel.Result) {
        try {
            val lastResult = BlockingEngine.instance.lastEvaluationResult
            result.success(lastResult)
        } catch (e: Exception) {
            result.success("not_required")
        }
    }

    private fun handleIsAccessibilityServiceEnabled(result: MethodChannel.Result) {
        try {
            val isEnabled = BlockingCapability.isAccessibilityServiceEnabled(context)
            result.success(isEnabled)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleIsIgnoringBatteryOptimizations(result: MethodChannel.Result) {
        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
            } else {
                true
            }
            result.success(isIgnoring)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun handleRequestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(intent)
                result.success(true)
            } else {
                result.success(true)
            }
        } catch (e: Exception) {
            try {
                val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(fallback)
                result.success(true)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }

    private fun handleConsumePendingActivityLogs(result: MethodChannel.Result) {
        try {
            val store = SharedPreferencesBlockingStore.create(context)
            val logs = store.consumePendingActivityLogs()
            result.success(logs)
        } catch (e: Exception) {
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    fun release() {
        executor.shutdown()
    }
}

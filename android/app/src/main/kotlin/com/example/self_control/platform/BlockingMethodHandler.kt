package com.example.self_control.platform

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.example.self_control.apps.InstalledAppProvider
import com.example.self_control.blocking.BlockingCapability
import com.example.self_control.blocking.BlockingEngine
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
            "openAccessibilitySettings" -> handleOpenAccessibilitySettings(result)
            "getInstalledApps" -> handleGetInstalledApps(result)
            "syncBlockedApps" -> handleSyncBlockedApps(call, result)
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

    fun release() {
        executor.shutdown()
    }
}

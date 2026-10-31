package com.example.self_control

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import com.example.self_control.platform.BlockingMethodHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "self_control/blocking"
    private var methodHandler: BlockingMethodHandler? = null
    private var methodChannel: MethodChannel? = null
    private var cachedInitialLockIntent: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        suppressWindowTransitions()
        cacheLockIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        val handler = BlockingMethodHandler(
            context = applicationContext,
            activityProvider = { this },
            initialLockIntentProvider = { consumeInitialLockIntent() }
        )
        methodHandler = handler
        channel.setMethodCallHandler(handler)
        methodChannel = channel
    }

    override fun getInitialRoute(): String {
        return if (intent?.getBooleanExtra("is_locked", false) == true) {
            "/locked"
        } else {
            super.getInitialRoute() ?: "/"
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        suppressWindowTransitions()
        handleLockIntent(intent)
    }

    fun consumeInitialLockIntent(): Map<String, Any?>? {
        val current = cachedInitialLockIntent
        cachedInitialLockIntent = null
        return current
    }

    private fun cacheLockIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("is_locked", false) == true) {
            val pkg = intent.getStringExtra("package_name") ?: ""
            val blockedAt = intent.getLongExtra("blocked_at", System.currentTimeMillis())
            cachedInitialLockIntent = mapOf(
                "packageName" to pkg,
                "blockedAt" to blockedAt
            )
        }
    }

    private fun handleLockIntent(intent: Intent) {
        if (intent.getBooleanExtra("is_locked", false)) {
            val pkg = intent.getStringExtra("package_name") ?: ""
            val blockedAt = intent.getLongExtra("blocked_at", System.currentTimeMillis())
            val channel = methodChannel
            if (channel != null) {
                channel.invokeMethod(
                    "onLockRequested",
                    mapOf(
                        "packageName" to pkg,
                        "blockedAt" to blockedAt
                    )
                )
            } else {
                val data = mapOf(
                    "packageName" to pkg,
                    "blockedAt" to blockedAt
                )
                cachedInitialLockIntent = data
                methodHandler?.setInitialLockIntent(data)
            }
        }
    }

    private fun suppressWindowTransitions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                overrideActivityTransition(Activity.OVERRIDE_TRANSITION_OPEN, 0, 0)
                overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
            } catch (_: Throwable) {
                @Suppress("DEPRECATION")
                overridePendingTransition(0, 0)
            }
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    override fun onDestroy() {
        methodHandler?.release()
        super.onDestroy()
    }
}

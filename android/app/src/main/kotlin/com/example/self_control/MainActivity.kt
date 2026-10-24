package com.example.self_control

import android.content.Intent
import com.example.self_control.platform.BlockingMethodHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "self_control/blocking"
    private var methodHandler: BlockingMethodHandler? = null
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        val handler = BlockingMethodHandler(applicationContext)
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
        handleLockIntent(intent)
    }

    private fun handleLockIntent(intent: Intent) {
        if (intent.getBooleanExtra("is_locked", false)) {
            val pkg = intent.getStringExtra("package_name") ?: ""
            val blockedAt = intent.getLongExtra("blocked_at", System.currentTimeMillis())
            methodChannel?.invokeMethod(
                "onLockRequested",
                mapOf(
                    "packageName" to pkg,
                    "blockedAt" to blockedAt
                )
            )
        }
    }

    override fun onDestroy() {
        methodHandler?.release()
        super.onDestroy()
    }
}

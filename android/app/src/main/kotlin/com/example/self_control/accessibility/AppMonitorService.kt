package com.example.self_control.accessibility

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.example.self_control.blocking.BlockingEngine

class AppMonitorService : AccessibilityService() {

    private val timeChangeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            if (action == Intent.ACTION_TIME_CHANGED || action == Intent.ACTION_TIMEZONE_CHANGED) {
                BlockingEngine.instance.onSystemTimeChanged()
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "AppMonitorService connected and bound")

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }
        registerReceiver(timeChangeReceiver, filter)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        AccessibilityEventHandler.handleEvent(this, event)
    }

    override fun onInterrupt() {
        Log.w(TAG, "AppMonitorService interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(timeChangeReceiver)
        } catch (_: Exception) {}
        if (instance === this) {
            instance = null
        }
        Log.i(TAG, "AppMonitorService destroyed")
    }

    companion object {
        private const val TAG = "AppMonitorService"

        @Volatile
        var instance: AppMonitorService? = null
            private set

        val isRunning: Boolean
            get() = instance != null

        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            if (isRunning) return true
            return isServiceEnabledInSettings(context)
        }

        fun isServiceEnabledInSettings(context: Context): Boolean {
            val expectedServiceName = ComponentName(context, AppMonitorService::class.java).flattenToString()
            val shortServiceName = "${context.packageName}/.${AppMonitorService::class.java.simpleName}"
            val enabledServicesSetting = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false

            val colonSplitter = TextUtils.SimpleStringSplitter(':')
            colonSplitter.setString(enabledServicesSetting)

            while (colonSplitter.hasNext()) {
                val componentName = colonSplitter.next()
                if (componentName.equals(expectedServiceName, ignoreCase = true) ||
                    componentName.equals(shortServiceName, ignoreCase = true)) {
                    return true
                }
            }
            return false
        }

        fun openAccessibilitySettings(context: Context): Boolean {
            return try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to open accessibility settings", e)
                false
            }
        }
    }
}

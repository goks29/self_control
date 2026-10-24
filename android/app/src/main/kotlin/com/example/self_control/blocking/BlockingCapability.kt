package com.example.self_control.blocking

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.example.self_control.accessibility.AppMonitorService

data class BlockingCapability(
    val mode: String = "accessibility",
    val serviceStatus: String,
    val limitations: List<String>
) {
    fun toMap(): Map<String, Any> {
        return mapOf(
            "mode" to mode,
            "serviceStatus" to serviceStatus,
            "limitations" to limitations
        )
    }

    companion object {
        fun detect(context: Context): BlockingCapability {
            val isEnabled = isAccessibilityServiceEnabled(context)
            val serviceStatus = if (isEnabled) "enabled" else "disabled"
            val limitations = mutableListOf<String>()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager != null && !powerManager.isIgnoringBatteryOptimizations(context.packageName)) {
                    limitations.add("battery_optimization")
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                limitations.add("background_activity_start")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!Settings.canDrawOverlays(context)) {
                    limitations.add("overlay_permission")
                }
            }

            return BlockingCapability(
                mode = "accessibility",
                serviceStatus = serviceStatus,
                limitations = limitations
            )
        }

        fun isAccessibilityServiceEnabled(context: Context): Boolean {
            return AppMonitorService.isAccessibilityServiceEnabled(context)
        }
    }
}

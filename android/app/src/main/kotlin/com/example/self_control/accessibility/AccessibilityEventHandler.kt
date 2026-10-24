package com.example.self_control.accessibility

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine

object AccessibilityEventHandler {

    private const val SYSTEM_UI_PACKAGE = "com.android.systemui"
    private var cachedLauncherPackage: String? = null

    fun handleEvent(context: Context, event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return
        }

        val packageName = event.packageName?.toString() ?: return
        if (packageName.isBlank()) {
            return
        }

        if (packageName == context.packageName) {
            return
        }

        if (packageName == SYSTEM_UI_PACKAGE) {
            return
        }

        if (isLauncherPackage(context, packageName)) {
            return
        }

        if (isInputMethodPackage(context, packageName)) {
            return
        }

        val decision = BlockingEngine.evaluate(packageName)
        if (decision is BlockingDecision.Block && decision.shouldBlock) {
            LockScreenLauncher.launchLockScreen(context, decision)
        }
    }

    private fun isLauncherPackage(context: Context, packageName: String): Boolean {
        if (packageName == cachedLauncherPackage) return true

        return try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            val resolveInfo = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            val defaultLauncher = resolveInfo?.activityInfo?.packageName
            if (defaultLauncher != null) {
                cachedLauncherPackage = defaultLauncher
                packageName == defaultLauncher
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isInputMethodPackage(context: Context, packageName: String): Boolean {
        return try {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                ?: return false
            val enabledImes = imm.enabledInputMethodList
            enabledImes.any { it.packageName == packageName }
        } catch (_: Exception) {
            false
        }
    }
}

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
    private const val IME_CACHE_TTL_MS = 60_000L
    private var cachedLauncherPackage: String? = null
    private var cachedImePackages: Set<String>? = null
    private var lastImeCacheTimeMs: Long = 0L

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
        val launcher = cachedLauncherPackage ?: run {
            try {
                val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                val resolveInfo = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
                val defaultLauncher = resolveInfo?.activityInfo?.packageName
                if (defaultLauncher != null) {
                    cachedLauncherPackage = defaultLauncher
                }
                defaultLauncher
            } catch (_: Exception) {
                null
            }
        }
        return packageName == launcher
    }

    private fun isInputMethodPackage(context: Context, packageName: String): Boolean {
        val now = System.currentTimeMillis()
        val cached = cachedImePackages
        if (cached != null && (now - lastImeCacheTimeMs) in 0 until IME_CACHE_TTL_MS) {
            return cached.contains(packageName)
        }

        return try {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                ?: return cached?.contains(packageName) ?: false
            val enabledImes = imm.enabledInputMethodList
            val imeSet = enabledImes.mapNotNull { it.packageName }.toSet()
            cachedImePackages = imeSet
            lastImeCacheTimeMs = now
            imeSet.contains(packageName)
        } catch (_: Exception) {
            cached?.contains(packageName) ?: false
        }
    }
}

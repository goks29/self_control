package com.example.self_control.accessibility

import android.app.ActivityOptions
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.self_control.MainActivity
import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.persistence.SharedPreferencesBlockingStore

object LockScreenLauncher {

    fun launchLockScreen(
        context: Context,
        decision: BlockingDecision.Block,
        engine: BlockingEngine = BlockingEngine.instance
    ): Boolean {
        if (!engine.shouldLaunchBlock(decision.packageName)) {
            return false
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION
            putExtra("is_locked", true)
            putExtra("package_name", decision.packageName)
            putExtra("blocked_at", decision.timestamp)
            putExtra("route", "/locked")
        }

        val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                val basic = ActivityOptions.makeBasic()
                try {
                    val method14 = ActivityOptions::class.java.getMethod(
                        "setPendingIntentBackgroundActivityStartMode",
                        Int::class.javaPrimitiveType
                    )
                    method14.invoke(basic, 1)
                } catch (_: Throwable) {
                }
                try {
                    val method15 = ActivityOptions::class.java.getMethod(
                        "setPendingIntentCreatorBackgroundActivityStartMode",
                        Int::class.javaPrimitiveType
                    )
                    method15.invoke(basic, 1)
                } catch (_: Throwable) {
                }
                basic.toBundle()
            } catch (_: Throwable) {
                null
            }
        } else {
            null
        }

        return try {
            if (options != null) {
                context.startActivity(intent, options)
            } else {
                context.startActivity(intent)
            }
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_CONFIRMED
            val store = SharedPreferencesBlockingStore.create(context)
            store.recordPendingActivityLog(
                decision.packageName,
                BlockingDecision.Block.STATUS_CONFIRMED,
                "lock_screen_launched",
                decision.timestamp
            )
            true
        } catch (e: ActivityNotFoundException) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            val store = SharedPreferencesBlockingStore.create(context)
            store.recordPendingActivityLog(
                decision.packageName,
                BlockingDecision.Block.STATUS_FAILED,
                "${e.javaClass.simpleName}: ${e.message}",
                decision.timestamp
            )
            false
        } catch (e: SecurityException) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            val store = SharedPreferencesBlockingStore.create(context)
            store.recordPendingActivityLog(
                decision.packageName,
                BlockingDecision.Block.STATUS_FAILED,
                "${e.javaClass.simpleName}: ${e.message}",
                decision.timestamp
            )
            false
        } catch (e: Exception) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            val store = SharedPreferencesBlockingStore.create(context)
            store.recordPendingActivityLog(
                decision.packageName,
                BlockingDecision.Block.STATUS_FAILED,
                "${e.javaClass.simpleName}: ${e.message}",
                decision.timestamp
            )
            false
        }
    }
}

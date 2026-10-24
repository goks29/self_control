package com.example.self_control.accessibility

import android.app.ActivityOptions
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.self_control.MainActivity
import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine

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
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("is_locked", true)
            putExtra("package_name", decision.packageName)
            putExtra("blocked_at", decision.timestamp)
            putExtra("route", "/locked")
        }

        val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                ActivityOptions.makeBasic().apply {
                    val method = ActivityOptions::class.java.getMethod(
                        "setPendingIntentBackgroundActivityStartMode",
                        Int::class.javaPrimitiveType
                    )
                    method.invoke(this, 1)
                }.toBundle()
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
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_ATTEMPTED
            true
        } catch (e: ActivityNotFoundException) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            false
        } catch (e: SecurityException) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            false
        } catch (e: Exception) {
            engine.lastEvaluationResult = BlockingDecision.Block.STATUS_FAILED
            false
        }
    }
}

package com.example.self_control.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.example.self_control.persistence.SharedPreferencesBlockingStore
import com.example.self_control.recovery.BootRecoveryController

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val action = intent?.action ?: return
        if (context == null) return

        if (!BootRecoveryController.isBootAction(action)) {
            return
        }

        try {
            val persistence = SharedPreferencesBlockingStore.create(context)
            val controller = BootRecoveryController(persistenceStore = persistence)
            controller.handleBoot(action)
        } catch (_: Exception) {
        }
    }
}

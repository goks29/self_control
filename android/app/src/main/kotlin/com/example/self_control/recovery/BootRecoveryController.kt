package com.example.self_control.recovery

import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.SystemTimeProvider
import com.example.self_control.blocking.TimeProvider
import com.example.self_control.persistence.BlockingPersistenceStore

class BootRecoveryController(
    private val persistenceStore: BlockingPersistenceStore,
    private val blockingEngine: BlockingEngine = BlockingEngine.instance,
    private val timeProvider: TimeProvider = SystemTimeProvider
) {
    companion object {
        const val ACTION_BOOT_COMPLETED = "android.intent.action.BOOT_COMPLETED"
        const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
        const val ACTION_HTC_QUICKBOOT_POWERON = "com.htc.intent.action.QUICKBOOT_POWERON"

        fun isBootAction(action: String?): Boolean {
            return action == ACTION_BOOT_COMPLETED ||
                   action == ACTION_QUICKBOOT_POWERON ||
                   action == ACTION_HTC_QUICKBOOT_POWERON
        }
    }

    fun handleBoot(action: String?): BootRecoveryResult {
        if (!isBootAction(action)) {
            return BootRecoveryResult(handled = false, restoredCount = 0, sessionStatus = null)
        }

        val nowMs = timeProvider.currentTimeMillis()

        val savedPackages = persistenceStore.getBlockedPackages()
        blockingEngine.syncBlockedApps(savedPackages)

        persistenceStore.clearExpiredTemporaryUnlocks(nowMs)
        val validUnlocks = persistenceStore.getSavedTemporaryUnlocks()
        blockingEngine.clearExpiredUnlocks(nowMs)
        for ((pkg, expirationMs) in validUnlocks) {
            val remainingSeconds = ((expirationMs - nowMs) / 1000L).toInt()
            if (remainingSeconds > 0) {
                blockingEngine.registerTemporaryUnlock(pkg, remainingSeconds, expirationMs)
            }
        }

        var currentSessionStatus: String? = null
        val activeSession = persistenceStore.getActiveSession()
        if (activeSession != null && activeSession.status == "active") {
            if (nowMs >= activeSession.endEpochMs && activeSession.endEpochMs > 0L) {
                persistenceStore.updateSessionStatus("completed")
                currentSessionStatus = "completed"
            } else {
                currentSessionStatus = "active"
            }
        }

        persistenceStore.recordPendingBootSync(nowMs)

        return BootRecoveryResult(
            handled = true,
            restoredCount = savedPackages.size,
            sessionStatus = currentSessionStatus
        )
    }
}

data class BootRecoveryResult(
    val handled: Boolean,
    val restoredCount: Int,
    val sessionStatus: String?
)

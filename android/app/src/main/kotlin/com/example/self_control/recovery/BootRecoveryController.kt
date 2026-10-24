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
        const val BOOT_DEDUPLICATION_WINDOW_MS = 10_000L

        @Volatile
        var lastBootHandledTimestampMs: Long = 0L
        private val lock = Any()

        fun isBootAction(action: String?): Boolean {
            return action == ACTION_BOOT_COMPLETED ||
                   action == ACTION_QUICKBOOT_POWERON ||
                   action == ACTION_HTC_QUICKBOOT_POWERON
        }

        fun reset() {
            synchronized(lock) {
                lastBootHandledTimestampMs = 0L
            }
        }
    }

    fun handleBoot(action: String?): BootRecoveryResult {
        if (!isBootAction(action)) {
            return BootRecoveryResult(handled = false, restoredCount = 0, sessionStatus = null)
        }

        val nowMs = timeProvider.currentTimeMillis()

        val savedPackages = try {
            persistenceStore.getBlockedPackages()
        } catch (_: Exception) {
            emptySet()
        }
        blockingEngine.syncBlockedApps(savedPackages)

        try {
            persistenceStore.clearExpiredTemporaryUnlocks(nowMs)
        } catch (_: Exception) {
        }

        val validUnlocks = try {
            persistenceStore.getSavedTemporaryUnlocks()
        } catch (_: Exception) {
            emptyMap()
        }
        blockingEngine.clearExpiredUnlocks(nowMs)
        for ((pkg, expirationMs) in validUnlocks) {
            if (expirationMs > nowMs) {
                val remainingSeconds = maxOf(1, (((expirationMs - nowMs) + 999L) / 1000L).toInt())
                blockingEngine.registerTemporaryUnlock(pkg, remainingSeconds, expirationMs)
            }
        }

        var currentSessionStatus: String? = null
        val activeSession = try {
            persistenceStore.getActiveSession()
        } catch (_: Exception) {
            null
        }
        if (activeSession != null && activeSession.status == "active") {
            if (nowMs >= activeSession.endEpochMs && activeSession.endEpochMs > 0L) {
                try {
                    persistenceStore.updateSessionStatus("completed")
                } catch (_: Exception) {
                }
                currentSessionStatus = "completed"
            } else {
                currentSessionStatus = "active"
            }
        }

        val shouldRecordSync = synchronized(lock) {
            if (lastBootHandledTimestampMs == 0L || Math.abs(nowMs - lastBootHandledTimestampMs) >= BOOT_DEDUPLICATION_WINDOW_MS) {
                lastBootHandledTimestampMs = nowMs
                true
            } else {
                false
            }
        }

        if (shouldRecordSync) {
            try {
                persistenceStore.recordPendingBootSync(nowMs)
            } catch (_: Exception) {
            }
        }

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

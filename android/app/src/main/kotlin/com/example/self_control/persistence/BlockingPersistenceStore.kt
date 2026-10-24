package com.example.self_control.persistence

interface BlockingPersistenceStore {
    fun getBlockedPackages(): Set<String>
    fun saveBlockedPackages(packages: Collection<String>)

    fun getActiveSession(): SessionData?
    fun saveActiveSession(startEpochMs: Long, endEpochMs: Long, status: String)
    fun updateSessionStatus(status: String)

    fun recordPendingBootSync(timestampMs: Long)
    fun consumePendingBootSyncs(): List<Long>

    fun getSavedTemporaryUnlocks(): Map<String, Long>
    fun saveTemporaryUnlock(packageName: String, expirationMs: Long)
    fun removeTemporaryUnlock(packageName: String)
    fun clearExpiredTemporaryUnlocks(nowMs: Long)
}

data class SessionData(
    val startEpochMs: Long,
    val endEpochMs: Long,
    val status: String
)

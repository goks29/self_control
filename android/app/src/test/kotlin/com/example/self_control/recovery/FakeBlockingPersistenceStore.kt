package com.example.self_control.recovery

import com.example.self_control.persistence.BlockingPersistenceStore
import com.example.self_control.persistence.SessionData

class FakeBlockingPersistenceStore : BlockingPersistenceStore {
    var savedPackages: MutableSet<String> = mutableSetOf()
    var savedSession: SessionData? = null
    val pendingBootSyncs: MutableList<Long> = mutableListOf()
    val savedUnlocks: MutableMap<String, Long> = mutableMapOf()

    override fun getBlockedPackages(): Set<String> = savedPackages.toSet()

    override fun saveBlockedPackages(packages: Collection<String>) {
        savedPackages = packages.toMutableSet()
    }

    override fun getActiveSession(): SessionData? = savedSession

    override fun saveActiveSession(startEpochMs: Long, endEpochMs: Long, status: String) {
        savedSession = SessionData(startEpochMs, endEpochMs, status)
    }

    override fun updateSessionStatus(status: String) {
        savedSession = savedSession?.copy(status = status)
    }

    override fun recordPendingBootSync(timestampMs: Long) {
        pendingBootSyncs.add(timestampMs)
    }

    override fun consumePendingBootSyncs(): List<Long> {
        val copy = pendingBootSyncs.toList()
        pendingBootSyncs.clear()
        return copy
    }

    override fun getSavedTemporaryUnlocks(): Map<String, Long> = savedUnlocks.toMap()

    override fun saveTemporaryUnlock(packageName: String, expirationMs: Long) {
        savedUnlocks[packageName] = expirationMs
    }

    override fun removeTemporaryUnlock(packageName: String) {
        savedUnlocks.remove(packageName)
    }

    override fun clearExpiredTemporaryUnlocks(nowMs: Long) {
        val iterator = savedUnlocks.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.value <= nowMs) {
                iterator.remove()
            }
        }
    }
}

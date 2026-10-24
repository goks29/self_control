package com.example.self_control.blocking

import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

class BlockingEngine(
    private val selfPackageName: String = DEFAULT_SELF_PACKAGE,
    private val timeProvider: TimeProvider = SystemTimeProvider,
    private val debounceFilter: DebounceFilter = DebounceFilter(timeProvider = timeProvider)
) {
    companion object {
        const val DEFAULT_SELF_PACKAGE = "com.example.self_control"

        @Volatile
        var instance: BlockingEngine = BlockingEngine()

        fun evaluate(packageName: String?): BlockingDecision = instance.evaluate(packageName)

        fun syncBlockedApps(packageNames: Collection<String>): Int = instance.syncBlockedApps(packageNames)

        fun shouldLaunchBlock(packageName: String): Boolean = instance.shouldLaunchBlock(packageName)

        fun reset() = instance.reset()
    }

    private val blockedPackagesRef = AtomicReference<Set<String>>(emptySet())
    private val temporaryUnlocks = ConcurrentHashMap<String, Long>()

    @Volatile
    var lastEvaluationResult: String = BlockingDecision.Allow.STATUS_NOT_REQUIRED

    val isBlockingActive: Boolean
        get() = blockedPackagesRef.get().isNotEmpty()

    val activePackage: String?
        get() = debounceFilter.getLastBlockedPackage()

    val blockedCount: Int
        get() = blockedPackagesRef.get().size

    fun syncBlockedApps(packageNames: Collection<String>): Int {
        val newSet = Collections.unmodifiableSet(packageNames.filter { it.isNotBlank() }.toHashSet())
        blockedPackagesRef.set(newSet)
        return newSet.size
    }

    fun getBlockedPackages(): Set<String> = blockedPackagesRef.get()

    fun registerTemporaryUnlock(packageName: String, durationSeconds: Int): Long {
        require(packageName.isNotBlank()) { "Package name cannot be blank" }
        require(durationSeconds > 0) { "Duration must be greater than zero" }

        val expirationMs = timeProvider.currentTimeMillis() + (durationSeconds * 1000L)
        temporaryUnlocks[packageName] = expirationMs
        return expirationMs
    }

    fun revokeTemporaryUnlock(packageName: String) {
        temporaryUnlocks.remove(packageName)
    }

    fun clearExpiredUnlocks(nowMs: Long = timeProvider.currentTimeMillis()) {
        val iterator = temporaryUnlocks.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.value <= nowMs) {
                iterator.remove()
            }
        }
    }

    fun isTemporaryUnlockActive(packageName: String, nowMs: Long = timeProvider.currentTimeMillis()): Boolean {
        val expiration = temporaryUnlocks[packageName] ?: return false
        return if (nowMs < expiration) {
            true
        } else {
            temporaryUnlocks.remove(packageName, expiration)
            false
        }
    }

    fun evaluate(packageName: String?): BlockingDecision {
        val now = timeProvider.currentTimeMillis()

        if (packageName.isNullOrBlank()) {
            lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
            return BlockingDecision.Allow(
                packageName = "",
                reason = BlockingDecision.Allow.REASON_EMPTY_PACKAGE,
                timestamp = now
            )
        }

        if (packageName == selfPackageName) {
            lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
            return BlockingDecision.Allow(
                packageName = packageName,
                reason = BlockingDecision.Allow.REASON_SELF_PACKAGE,
                timestamp = now
            )
        }

        val currentBlocked = blockedPackagesRef.get()
        if (!currentBlocked.contains(packageName)) {
            lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
            return BlockingDecision.Allow(
                packageName = packageName,
                reason = BlockingDecision.Allow.REASON_NOT_RESTRICTED,
                timestamp = now
            )
        }

        val unlockExpiration = temporaryUnlocks[packageName]
        if (unlockExpiration != null) {
            if (now < unlockExpiration) {
                lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
                return BlockingDecision.Allow(
                    packageName = packageName,
                    reason = BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK,
                    timestamp = now
                )
            } else {
                temporaryUnlocks.remove(packageName, unlockExpiration)
            }
        }

        lastEvaluationResult = BlockingDecision.Block.STATUS_ATTEMPTED
        return BlockingDecision.Block(
            packageName = packageName,
            reason = BlockingDecision.Block.REASON_POLICY_RESTRICTED,
            timestamp = now
        )
    }

    fun shouldLaunchBlock(packageName: String): Boolean {
        return debounceFilter.shouldProceed(packageName)
    }

    fun getCurrentState(): Map<String, Any?> {
        val now = timeProvider.currentTimeMillis()
        clearExpiredUnlocks(now)
        return mapOf(
            "blockedCount" to blockedPackagesRef.get().size,
            "temporaryUnlocksCount" to temporaryUnlocks.size,
            "lastBlockedPackage" to debounceFilter.getLastBlockedPackage(),
            "lastBlockedTimeMs" to debounceFilter.getLastBlockedTimeMs(),
            "lastResult" to lastEvaluationResult
        )
    }

    fun reset() {
        blockedPackagesRef.set(emptySet())
        temporaryUnlocks.clear()
        lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
        debounceFilter.reset()
    }
}

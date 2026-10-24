package com.example.self_control.blocking

import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference

data class ActiveSessionState(
    val isStrictSessionActive: Boolean = false,
    val sessionEndEpochMs: Long? = null,
    val scheduleRule: ScheduleRule? = null
)

data class ScheduleRule(
    val startMinute: Int,
    val endMinute: Int,
    val daysMask: Int,
    val isEnabled: Boolean = true
) {
    fun isActiveAt(epochMs: Long): Boolean {
        if (!isEnabled) return false
        val cal = java.util.Calendar.getInstance().apply { timeInMillis = epochMs }
        val currentMinute = cal.get(java.util.Calendar.HOUR_OF_DAY) * 60 + cal.get(java.util.Calendar.MINUTE)
        val calDay = cal.get(java.util.Calendar.DAY_OF_WEEK)
        val weekday = if (calDay == java.util.Calendar.SUNDAY) 7 else calDay - 1

        return if (startMinute < endMinute) {
            val isTodayEnabled = (daysMask and (1 shl (weekday - 1))) != 0
            isTodayEnabled && (currentMinute in startMinute until endMinute)
        } else {
            if (currentMinute >= startMinute) {
                (daysMask and (1 shl (weekday - 1))) != 0
            } else if (currentMinute < endMinute) {
                val prevDay = if (weekday == 1) 7 else weekday - 1
                (daysMask and (1 shl (prevDay - 1))) != 0
            } else {
                false
            }
        }
    }
}

class BlockingEngine(
    private val selfPackageName: String = DEFAULT_SELF_PACKAGE,
    private val timeProvider: TimeProvider = SystemTimeProvider,
    private val debounceFilter: DebounceFilter = DebounceFilter(timeProvider = timeProvider)
) {
    companion object {
        const val DEFAULT_SELF_PACKAGE = "com.example.self_control"
        const val CLOCK_TAMPER_TOLERANCE_MS = 3000L

        @Volatile
        var instance: BlockingEngine = BlockingEngine()

        fun evaluate(packageName: String?): BlockingDecision = instance.evaluate(packageName)

        fun syncBlockedApps(packageNames: Collection<String>): Int = instance.syncBlockedApps(packageNames)

        fun shouldLaunchBlock(packageName: String): Boolean = instance.shouldLaunchBlock(packageName)

        fun reset() = instance.reset()
    }

    private val blockedPackagesRef = AtomicReference<Set<String>>(emptySet())
    private val temporaryUnlocks = ConcurrentHashMap<String, Long>()
    private val sessionStateRef = AtomicReference(ActiveSessionState())

    @Volatile
    private var lastObservedTimeMs: Long = 0L

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

    fun syncActiveSessions(
        isStrictSessionActive: Boolean,
        sessionEndEpochMs: Long?,
        scheduleRule: ScheduleRule?
    ) {
        sessionStateRef.set(
            ActiveSessionState(
                isStrictSessionActive = isStrictSessionActive,
                sessionEndEpochMs = sessionEndEpochMs,
                scheduleRule = scheduleRule
            )
        )
    }

    fun registerTemporaryUnlock(
        packageName: String,
        durationSeconds: Int = 0,
        expiresAtEpochMs: Long? = null
    ): Long {
        require(packageName.isNotBlank()) { "Package name cannot be blank" }

        val expirationMs = if (expiresAtEpochMs != null && expiresAtEpochMs > 0L) {
            expiresAtEpochMs
        } else {
            require(durationSeconds > 0) { "Duration must be greater than zero" }
            timeProvider.currentTimeMillis() + (durationSeconds * 1000L)
        }

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
        if (lastObservedTimeMs > 0L && nowMs < lastObservedTimeMs - CLOCK_TAMPER_TOLERANCE_MS) {
            temporaryUnlocks.clear()
        }
        lastObservedTimeMs = maxOf(lastObservedTimeMs, nowMs)

        val expiration = temporaryUnlocks[packageName] ?: return false
        return if (nowMs < expiration) {
            true
        } else {
            temporaryUnlocks.remove(packageName, expiration)
            false
        }
    }

    fun onSystemTimeChanged() {
        temporaryUnlocks.clear()
        lastObservedTimeMs = timeProvider.currentTimeMillis()
    }

    fun evaluate(packageName: String?): BlockingDecision {
        val now = timeProvider.currentTimeMillis()

        if (lastObservedTimeMs > 0L && now < lastObservedTimeMs - CLOCK_TAMPER_TOLERANCE_MS) {
            temporaryUnlocks.clear()
        }
        lastObservedTimeMs = maxOf(lastObservedTimeMs, now)

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

        val sessionState = sessionStateRef.get()
        val isBlockedBySession = sessionState.isStrictSessionActive &&
            (sessionState.sessionEndEpochMs == null || now < sessionState.sessionEndEpochMs)
        val isBlockedBySchedule = sessionState.scheduleRule?.isActiveAt(now) == true
        val shouldBlock = isBlockedBySession || isBlockedBySchedule ||
            (sessionState.sessionEndEpochMs == null && sessionState.scheduleRule == null)

        if (shouldBlock) {
            lastEvaluationResult = BlockingDecision.Block.STATUS_ATTEMPTED
            return BlockingDecision.Block(
                packageName = packageName,
                reason = BlockingDecision.Block.REASON_POLICY_RESTRICTED,
                timestamp = now
            )
        }

        return BlockingDecision.Allow(
            packageName = packageName,
            reason = BlockingDecision.Allow.REASON_NOT_RESTRICTED,
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
        sessionStateRef.set(ActiveSessionState())
        lastObservedTimeMs = 0L
        lastEvaluationResult = BlockingDecision.Allow.STATUS_NOT_REQUIRED
        debounceFilter.reset()
    }
}

package com.example.self_control.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class TemporaryUnlockSyncTest {
    private lateinit var fakeTime: FakeTimeProvider
    private lateinit var engine: BlockingEngine

    @Before
    fun setup() {
        fakeTime = FakeTimeProvider(1_000_000L)
        engine = BlockingEngine(
            selfPackageName = "com.example.self_control",
            timeProvider = fakeTime,
            debounceFilter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)
        )
    }

    @Test
    fun registerTemporaryUnlockWithExplicitExpirationAndAutoPruneBoundary() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        val expiration = 1_060_000L
        engine.registerTemporaryUnlock("com.instagram.android", expiresAtEpochMs = expiration)

        fakeTime.nowMs = 1_059_999L
        val allowDecision = engine.evaluate("com.instagram.android")
        assertFalse(allowDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, allowDecision.reason)

        fakeTime.nowMs = 1_060_000L
        val blockDecision = engine.evaluate("com.instagram.android")
        assertTrue(blockDecision.shouldBlock)
        assertEquals(BlockingDecision.Block.REASON_POLICY_RESTRICTED, blockDecision.reason)
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))
    }

    @Test
    fun syncActiveSessionsBlocksWhenSessionIsActive() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.syncActiveSessions(
            isStrictSessionActive = true,
            sessionEndEpochMs = 2_000_000L,
            scheduleRule = null
        )

        fakeTime.nowMs = 1_500_000L
        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
    }

    @Test
    fun syncActiveSessionsAllowsWhenStrictSessionEnded() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.syncActiveSessions(
            isStrictSessionActive = true,
            sessionEndEpochMs = 1_200_000L,
            scheduleRule = ScheduleRule(
                startMinute = 0,
                endMinute = 0,
                daysMask = 0,
                isEnabled = false
            )
        )

        fakeTime.nowMs = 1_300_000L
        val decision = engine.evaluate("com.instagram.android")
        assertFalse(decision.shouldBlock)
    }

    @Test
    fun scheduleRuleEvaluatesStandardWindow() {
        val rule = ScheduleRule(
            startMinute = 540,
            endMinute = 1020,
            daysMask = 127,
            isEnabled = true
        )
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.HOUR_OF_DAY, 10)
        cal.set(java.util.Calendar.MINUTE, 0)
        assertTrue(rule.isActiveAt(cal.timeInMillis))

        cal.set(java.util.Calendar.HOUR_OF_DAY, 18)
        assertFalse(rule.isActiveAt(cal.timeInMillis))
    }

    @Test
    fun scheduleRuleEvaluatesOvernightWindowAcrossMidnight() {
        val rule = ScheduleRule(
            startMinute = 1320,
            endMinute = 360,
            daysMask = 127,
            isEnabled = true
        )
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.HOUR_OF_DAY, 23)
        cal.set(java.util.Calendar.MINUTE, 0)
        assertTrue(rule.isActiveAt(cal.timeInMillis))

        cal.set(java.util.Calendar.HOUR_OF_DAY, 2)
        assertTrue(rule.isActiveAt(cal.timeInMillis))

        cal.set(java.util.Calendar.HOUR_OF_DAY, 12)
        assertFalse(rule.isActiveAt(cal.timeInMillis))
    }
}

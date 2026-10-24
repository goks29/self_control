package com.example.self_control.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BlockingEngineAdversarialTest {
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
    fun nativeTemporaryUnlockPurgeOnClockRollbackBeyondTolerance() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 600)

        fakeTime.advance(10_000L)
        assertFalse(engine.evaluate("com.instagram.android").shouldBlock)
        assertTrue(engine.isTemporaryUnlockActive("com.instagram.android"))

        fakeTime.nowMs = 1_010_000L - 3001L
        val decision = engine.evaluate("com.instagram.android")

        assertTrue(decision.shouldBlock)
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))
    }

    @Test
    fun clockRollbackWithinToleranceDoesNotPurgeTemporaryUnlock() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 600)

        fakeTime.advance(10_000L)
        assertFalse(engine.evaluate("com.instagram.android").shouldBlock)

        fakeTime.nowMs = 1_010_000L - 2000L
        val decision = engine.evaluate("com.instagram.android")

        assertFalse(decision.shouldBlock)
        assertTrue(engine.isTemporaryUnlockActive("com.instagram.android"))
    }

    @Test
    fun subsequentUnlocksAfterClockRollbackMustNotBePermanentlyBlocked() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 600)

        engine.evaluate("com.instagram.android")

        fakeTime.nowMs = 500_000L
        val rollbackDecision = engine.evaluate("com.instagram.android")
        assertTrue(rollbackDecision.shouldBlock)

        fakeTime.advance(1000L)
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 300)

        fakeTime.advance(1000L)
        val nextDecision = engine.evaluate("com.instagram.android")

        assertFalse(nextDecision.shouldBlock)
    }
}

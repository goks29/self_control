package com.example.self_control.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BlockingEngineTest {
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
    fun evaluateNullOrBlankPackageReturnsAllow() {
        val decisionNull = engine.evaluate(null)
        assertFalse(decisionNull.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, decisionNull.reason)

        val decisionBlank = engine.evaluate("   ")
        assertFalse(decisionBlank.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, decisionBlank.reason)
    }

    @Test
    fun evaluateSelfPackageReturnsAllow() {
        val decision = engine.evaluate("com.example.self_control")
        assertFalse(decision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_SELF_PACKAGE, decision.reason)
    }

    @Test
    fun evaluateUnblockedPackageReturnsAllow() {
        engine.syncBlockedApps(listOf("com.instagram.android", "com.tiktok.android"))
        val decision = engine.evaluate("com.whatsapp")
        assertFalse(decision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_NOT_RESTRICTED, decision.reason)
    }

    @Test
    fun evaluateBlockedPackageReturnsBlock() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
        assertEquals(BlockingDecision.Block.REASON_POLICY_RESTRICTED, decision.reason)
        assertEquals("attempted", engine.lastEvaluationResult)
    }

    @Test
    fun evaluatePackageWithActiveTemporaryUnlockReturnsAllow() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 300)

        fakeTime.advance(100_000L)
        val decision = engine.evaluate("com.instagram.android")
        assertFalse(decision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, decision.reason)
    }

    @Test
    fun evaluatePackageWithExpiredTemporaryUnlockReturnsBlockAndPrunes() {
        engine.syncBlockedApps(listOf("com.instagram.android"))
        engine.registerTemporaryUnlock("com.instagram.android", durationSeconds = 300)

        fakeTime.advance(301_000L)
        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))
    }

    @Test
    fun syncBlockedAppsAtomicallyReplacesExistingBlockedList() {
        engine.syncBlockedApps(listOf("com.app.a", "com.app.b"))
        assertTrue(engine.getBlockedPackages().contains("com.app.a"))

        engine.syncBlockedApps(listOf("com.app.c"))
        assertFalse(engine.getBlockedPackages().contains("com.app.a"))
        assertTrue(engine.getBlockedPackages().contains("com.app.c"))
    }

    @Test
    fun debounceSuppressesLaunchWithin1500msForSamePackage() {
        assertTrue(engine.shouldLaunchBlock("com.instagram.android"))

        fakeTime.advance(1000L)
        assertFalse(engine.shouldLaunchBlock("com.instagram.android"))

        fakeTime.advance(600L)
        assertTrue(engine.shouldLaunchBlock("com.instagram.android"))
    }

    @Test
    fun debounceAllowsDifferentPackageImmediately() {
        assertTrue(engine.shouldLaunchBlock("com.instagram.android"))

        fakeTime.advance(200L)
        assertTrue(engine.shouldLaunchBlock("com.tiktok.android"))
    }

    @Test
    fun clearExpiredUnlocksRemovesOnlyExpired() {
        engine.registerTemporaryUnlock("com.app.one", durationSeconds = 100)
        engine.registerTemporaryUnlock("com.app.two", durationSeconds = 300)

        fakeTime.advance(150_000L)
        engine.clearExpiredUnlocks()

        assertFalse(engine.isTemporaryUnlockActive("com.app.one"))
        assertTrue(engine.isTemporaryUnlockActive("com.app.two"))
    }

    @Test
    fun getCurrentStateReturnsExpectedValues() {
        engine.syncBlockedApps(listOf("com.app.one", "com.app.two"))
        engine.registerTemporaryUnlock("com.app.one", durationSeconds = 300)
        engine.evaluate("com.app.two")

        val state = engine.getCurrentState()
        assertEquals(2, state["blockedCount"])
        assertEquals(1, state["temporaryUnlocksCount"])
        assertEquals("attempted", state["lastResult"])
    }
}

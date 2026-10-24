package com.example.self_control.receiver

import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.DebounceFilter
import com.example.self_control.blocking.FakeTimeProvider
import com.example.self_control.persistence.SessionData
import com.example.self_control.recovery.BootRecoveryController
import com.example.self_control.recovery.FakeBlockingPersistenceStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BootRecoveryControllerTest {
    private lateinit var fakeTime: FakeTimeProvider
    private lateinit var engine: BlockingEngine
    private lateinit var fakePersistence: FakeBlockingPersistenceStore
    private lateinit var controller: BootRecoveryController

    @Before
    fun setup() {
        fakeTime = FakeTimeProvider(1_000_000L)
        engine = BlockingEngine(
            selfPackageName = "com.example.self_control",
            timeProvider = fakeTime,
            debounceFilter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)
        )
        fakePersistence = FakeBlockingPersistenceStore()
        controller = BootRecoveryController(
            persistenceStore = fakePersistence,
            blockingEngine = engine,
            timeProvider = fakeTime
        )
    }

    @Test
    fun ignoreNonBootIntentAction() {
        fakePersistence.saveBlockedPackages(listOf("com.instagram.android"))
        val result = controller.handleBoot("android.intent.action.TIME_TICK")

        assertFalse(result.handled)
        assertEquals(0, result.restoredCount)
        assertFalse(engine.getBlockedPackages().contains("com.instagram.android"))
        assertTrue(fakePersistence.pendingBootSyncs.isEmpty())
    }

    @Test
    fun handleBootCompletedRestoresBlockedPackages() {
        fakePersistence.saveBlockedPackages(listOf("com.instagram.android", "com.tiktok.android"))
        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertTrue(result.handled)
        assertEquals(2, result.restoredCount)
        assertTrue(engine.getBlockedPackages().contains("com.instagram.android"))
        assertTrue(engine.getBlockedPackages().contains("com.tiktok.android"))
        assertEquals(listOf(1_000_000L), fakePersistence.pendingBootSyncs)
    }

    @Test
    fun handleVendorQuickBootPoweronRestoresBlockedPackages() {
        fakePersistence.saveBlockedPackages(listOf("com.twitter.android"))
        val resultQuick = controller.handleBoot(BootRecoveryController.ACTION_QUICKBOOT_POWERON)
        assertTrue(resultQuick.handled)
        assertTrue(engine.getBlockedPackages().contains("com.twitter.android"))

        engine.reset()
        val resultHtc = controller.handleBoot(BootRecoveryController.ACTION_HTC_QUICKBOOT_POWERON)
        assertTrue(resultHtc.handled)
        assertTrue(engine.getBlockedPackages().contains("com.twitter.android"))
    }

    @Test
    fun activeSessionRemainsActiveIfEndTimeInFuture() {
        fakePersistence.savedSession = SessionData(
            startEpochMs = 900_000L,
            endEpochMs = 1_500_000L,
            status = "active"
        )
        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertEquals("active", result.sessionStatus)
        assertEquals("active", fakePersistence.savedSession?.status)
    }

    @Test
    fun activeSessionTransitionsToCompletedIfEndTimeElapsed() {
        fakePersistence.savedSession = SessionData(
            startEpochMs = 800_000L,
            endEpochMs = 950_000L,
            status = "active"
        )
        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertEquals("completed", result.sessionStatus)
        assertEquals("completed", fakePersistence.savedSession?.status)
    }

    @Test
    fun temporaryUnlockPrunedIfExpiredOnBoot() {
        fakePersistence.saveBlockedPackages(listOf("com.instagram.android"))
        fakePersistence.saveTemporaryUnlock("com.instagram.android", expirationMs = 900_000L)

        controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertFalse(fakePersistence.savedUnlocks.containsKey("com.instagram.android"))
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))

        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
    }

    @Test
    fun temporaryUnlockRestoredIfStillValidOnBoot() {
        fakePersistence.saveBlockedPackages(listOf("com.instagram.android"))
        fakePersistence.saveTemporaryUnlock("com.instagram.android", expirationMs = 1_200_000L)

        controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertTrue(fakePersistence.savedUnlocks.containsKey("com.instagram.android"))
        assertTrue(engine.isTemporaryUnlockActive("com.instagram.android"))

        val decision = engine.evaluate("com.instagram.android")
        assertFalse(decision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, decision.reason)
    }
}

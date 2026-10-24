package com.example.self_control.recovery

import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.DebounceFilter
import com.example.self_control.blocking.FakeTimeProvider
import com.example.self_control.persistence.SessionData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class BootRecoveryHandleBootBugReproTest {

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
        BootRecoveryController.reset()
        fakePersistence = FakeBlockingPersistenceStore()
        controller = BootRecoveryController(
            persistenceStore = fakePersistence,
            blockingEngine = engine,
            timeProvider = fakeTime
        )
    }

    @Test
    fun handleBootMustRestoreStrictSessionActiveInBlockingEngine() {
        fakePersistence.saveBlockedPackages(listOf("com.instagram.android"))
        fakePersistence.savedSession = SessionData(
            startEpochMs = 900_000L,
            endEpochMs = 1_500_000L,
            status = "active"
        )

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertEquals("active", result.sessionStatus)
        assertTrue(engine.isStrictSessionActive)
    }
}

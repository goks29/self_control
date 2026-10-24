package com.example.self_control.blocking

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DebounceFilterAdversarialTest {

    @Test
    fun rapidBurstInterceptionAcrossThreads() {
        val filter = DebounceFilter(thresholdMs = 1500L)
        val threadCount = 10
        val eventsPerThread = 100
        val totalEvents = threadCount * eventsPerThread
        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(totalEvents)
        val proceedCount = AtomicInteger(0)

        for (i in 0 until totalEvents) {
            executor.submit {
                try {
                    startLatch.await()
                    if (filter.shouldProceed("com.example.burst")) {
                        proceedCount.incrementAndGet()
                    }
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        val finished = doneLatch.await(5, TimeUnit.SECONDS)
        executor.shutdown()

        assertTrue(finished)
        assertEquals(1, proceedCount.get())
    }

    @Test
    fun backwardClockTamperingDoesNotStallAndResetsCleanly() {
        val fakeTime = FakeTimeProvider(10_000L)
        val filter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)

        assertTrue(filter.shouldProceed("com.example.target"))
        assertEquals(10_000L, filter.getLastBlockedTimeMs())

        fakeTime.advance(-8_000L)
        assertEquals(2_000L, fakeTime.currentTimeMillis())

        assertTrue(filter.shouldProceed("com.example.target"))
        assertEquals(2_000L, filter.getLastBlockedTimeMs())

        fakeTime.advance(500L)
        assertEquals(2_500L, fakeTime.currentTimeMillis())
        assertFalse(filter.shouldProceed("com.example.target"))

        fakeTime.advance(1_600L)
        assertEquals(4_100L, fakeTime.currentTimeMillis())
        assertTrue(filter.shouldProceed("com.example.target"))
        assertEquals(4_100L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun alternatingPackageStreamsTransitionsTriggerBlockingImmediately() {
        val fakeTime = FakeTimeProvider(1_000L)
        val filter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)

        assertTrue(filter.shouldProceed("com.app.a"))
        assertEquals("com.app.a", filter.getLastBlockedPackage())

        fakeTime.advance(50L)
        assertTrue(filter.shouldProceed("com.app.b"))
        assertEquals("com.app.b", filter.getLastBlockedPackage())

        fakeTime.advance(50L)
        assertTrue(filter.shouldProceed("com.app.a"))
        assertEquals("com.app.a", filter.getLastBlockedPackage())

        fakeTime.advance(50L)
        assertFalse(filter.shouldProceed("com.app.a"))

        fakeTime.advance(50L)
        assertTrue(filter.shouldProceed("com.app.b"))
    }

    @Test
    fun selfPackageLoopPreventionInBlockingEngine() {
        val engine = BlockingEngine(
            selfPackageName = "com.example.self_control",
            timeProvider = FakeTimeProvider(1_000_000L)
        )
        engine.syncBlockedApps(listOf("com.example.self_control", "com.android.systemui", "com.blocked.app"))

        val selfDecision = engine.evaluate("com.example.self_control")
        assertFalse(selfDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_SELF_PACKAGE, selfDecision.reason)

        val emptyDecision = engine.evaluate("")
        assertFalse(emptyDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, emptyDecision.reason)

        val normalDecision = engine.evaluate("com.blocked.app")
        assertTrue(normalDecision.shouldBlock)
        assertEquals(BlockingDecision.Block.REASON_POLICY_RESTRICTED, normalDecision.reason)
    }

    @Test
    fun minorClockJitterWithinDebounceWindowIsSuppressed() {
        val fakeTime = FakeTimeProvider(10_000L)
        val filter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)

        assertTrue(filter.shouldProceed("com.example.jitter"))
        assertEquals(10_000L, filter.getLastBlockedTimeMs())

        fakeTime.advance(-2L)
        assertEquals(9_998L, fakeTime.currentTimeMillis())
        assertFalse(filter.shouldProceed("com.example.jitter"))

        fakeTime.advance(-500L)
        assertEquals(9_498L, fakeTime.currentTimeMillis())
        assertFalse(filter.shouldProceed("com.example.jitter"))

        fakeTime.advance(-1_000L)
        assertEquals(8_498L, fakeTime.currentTimeMillis())
        assertTrue(filter.shouldProceed("com.example.jitter"))
        assertEquals(8_498L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun concurrentTimestampInversionHandledCleanly() {
        val filter = DebounceFilter(thresholdMs = 1500L)
        val threadCount = 20
        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        val proceedCount = AtomicInteger(0)

        for (i in 0 until threadCount) {
            executor.submit {
                try {
                    startLatch.await()
                    if (filter.shouldProceed("com.example.race")) {
                        proceedCount.incrementAndGet()
                    }
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        assertTrue(doneLatch.await(5, TimeUnit.SECONDS))
        executor.shutdown()

        assertEquals(1, proceedCount.get())
    }
}


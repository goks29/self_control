package com.example.self_control.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class BlockingEngineStressTest {

    private class AtomicTimeProvider(initialMs: Long = 1_000_000L) : TimeProvider {
        private val timeMs = AtomicLong(initialMs)

        override fun currentTimeMillis(): Long = timeMs.get()

        fun advance(delta: Long): Long = timeMs.addAndGet(delta)

        fun set(value: Long) {
            timeMs.set(value)
        }
    }

    @Test
    fun temporaryUnlockExactBoundaryTransitions() {
        val timeProvider = FakeTimeProvider(1_000_000L)
        val engine = BlockingEngine(timeProvider = timeProvider)
        val targetPackage = "com.test.restricted"

        engine.syncBlockedApps(listOf(targetPackage))
        val expirationMs = engine.registerTemporaryUnlock(targetPackage, durationSeconds = 60)
        assertEquals(1_060_000L, expirationMs)

        timeProvider.nowMs = expirationMs - 1L
        assertTrue(engine.isTemporaryUnlockActive(targetPackage))
        val beforeDecision = engine.evaluate(targetPackage)
        assertFalse(beforeDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, beforeDecision.reason)

        timeProvider.nowMs = expirationMs
        assertFalse(engine.isTemporaryUnlockActive(targetPackage))
        val atDecision = engine.evaluate(targetPackage)
        assertTrue(atDecision.shouldBlock)
        assertEquals(BlockingDecision.Block.REASON_POLICY_RESTRICTED, atDecision.reason)
        assertEquals(0, engine.getCurrentState()["temporaryUnlocksCount"])

        timeProvider.nowMs = expirationMs + 1L
        assertFalse(engine.isTemporaryUnlockActive(targetPackage))
        val afterDecision = engine.evaluate(targetPackage)
        assertTrue(afterDecision.shouldBlock)
        assertEquals(BlockingDecision.Block.REASON_POLICY_RESTRICTED, afterDecision.reason)
    }

    @Test
    fun temporaryUnlockAutoPrunesExpiredEntries() {
        val timeProvider = FakeTimeProvider(1_000_000L)
        val engine = BlockingEngine(timeProvider = timeProvider)

        engine.syncBlockedApps(listOf("com.app.a", "com.app.b", "com.app.c"))
        engine.registerTemporaryUnlock("com.app.a", durationSeconds = 10)
        engine.registerTemporaryUnlock("com.app.b", durationSeconds = 20)
        engine.registerTemporaryUnlock("com.app.c", durationSeconds = 30)

        timeProvider.advance(15_000L)

        val decisionA = engine.evaluate("com.app.a")
        assertTrue(decisionA.shouldBlock)

        val decisionB = engine.evaluate("com.app.b")
        assertFalse(decisionB.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, decisionB.reason)

        timeProvider.advance(10_000L)
        val state = engine.getCurrentState()
        assertEquals(1, state["temporaryUnlocksCount"])
        assertTrue(engine.isTemporaryUnlockActive("com.app.c"))
        assertFalse(engine.isTemporaryUnlockActive("com.app.b"))
    }

    @Test
    fun inputEdgeCasesHandling() {
        val engine = BlockingEngine(
            selfPackageName = "com.example.self_control",
            timeProvider = FakeTimeProvider(1_000_000L)
        )
        engine.syncBlockedApps(listOf("com.blocked.app"))

        val emptyDecision = engine.evaluate("")
        assertFalse(emptyDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, emptyDecision.reason)
        assertEquals("", emptyDecision.packageName)

        val whitespaceDecision = engine.evaluate("   \t\n  ")
        assertFalse(whitespaceDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, whitespaceDecision.reason)
        assertEquals("", whitespaceDecision.packageName)

        val nullDecision = engine.evaluate(null)
        assertFalse(nullDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_EMPTY_PACKAGE, nullDecision.reason)
        assertEquals("", nullDecision.packageName)

        val selfDecision = engine.evaluate("com.example.self_control")
        assertFalse(selfDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_SELF_PACKAGE, selfDecision.reason)
        assertEquals("com.example.self_control", selfDecision.packageName)

        val unknownDecision = engine.evaluate("com.unrestricted.app")
        assertFalse(unknownDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_NOT_RESTRICTED, unknownDecision.reason)
        assertEquals("com.unrestricted.app", unknownDecision.packageName)
    }

    @Test
    fun syncBlockedAppsHandlesDuplicatesBlanksAndWhitespace() {
        val engine = BlockingEngine()
        val rawList = listOf(
            "com.app.one",
            "com.app.two",
            "com.app.one",
            "",
            "   ",
            "com.app.three",
            "com.app.two",
            "\t\n"
        )

        val count = engine.syncBlockedApps(rawList)
        assertEquals(3, count)
        assertEquals(3, engine.blockedCount)

        val blockedSet = engine.getBlockedPackages()
        assertTrue(blockedSet.contains("com.app.one"))
        assertTrue(blockedSet.contains("com.app.two"))
        assertTrue(blockedSet.contains("com.app.three"))
        assertFalse(blockedSet.contains(""))
        assertFalse(blockedSet.contains("   "))
    }

    @Test
    fun registerTemporaryUnlockRejectsInvalidInputs() {
        val engine = BlockingEngine()

        try {
            engine.registerTemporaryUnlock("", 60)
            fail("Expected IllegalArgumentException for empty package")
        } catch (_: IllegalArgumentException) {
        }

        try {
            engine.registerTemporaryUnlock("   ", 60)
            fail("Expected IllegalArgumentException for blank package")
        } catch (_: IllegalArgumentException) {
        }

        try {
            engine.registerTemporaryUnlock("com.valid.app", 0)
            fail("Expected IllegalArgumentException for zero duration")
        } catch (_: IllegalArgumentException) {
        }

        try {
            engine.registerTemporaryUnlock("com.valid.app", -10)
            fail("Expected IllegalArgumentException for negative duration")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test
    fun largeScaleSyncAndHighThroughputEvaluation() {
        val timeProvider = FakeTimeProvider(1_000_000L)
        val engine = BlockingEngine(timeProvider = timeProvider)

        val largePackageList = (1..5000).map { "com.example.app$it" }
        val syncStart = System.nanoTime()
        val syncedCount = engine.syncBlockedApps(largePackageList)
        val syncDurationMs = (System.nanoTime() - syncStart) / 1_000_000.0

        assertEquals(5000, syncedCount)
        assertEquals(5000, engine.blockedCount)
        assertTrue(syncDurationMs < 200.0)

        engine.registerTemporaryUnlock("com.example.app100", durationSeconds = 300)

        val evaluationCount = 100_000
        val evalStart = System.nanoTime()
        var blockedCounter = 0
        var allowedCounter = 0

        for (i in 0 until evaluationCount) {
            val pkg = when (i % 5) {
                0 -> "com.example.app${(i % 5000) + 1}"
                1 -> "com.example.app100"
                2 -> "com.unrestricted.package$i"
                3 -> "com.example.self_control"
                else -> ""
            }
            val decision = engine.evaluate(pkg)
            if (decision.shouldBlock) {
                blockedCounter++
            } else {
                allowedCounter++
            }
        }

        val totalEvalTimeMs = (System.nanoTime() - evalStart) / 1_000_000.0
        val avgEvalTimeUs = (totalEvalTimeMs * 1000.0) / evaluationCount

        assertTrue(totalEvalTimeMs < 2000.0)
        assertTrue(avgEvalTimeUs < 50.0)
        assertTrue(blockedCounter > 0)
        assertTrue(allowedCounter > 0)
        assertEquals(evaluationCount, blockedCounter + allowedCounter)
    }

    @Test
    fun concurrentSyncAndEvaluateUnderHeavyContention() {
        val timeProvider = AtomicTimeProvider(1_000_000L)
        val engine = BlockingEngine(timeProvider = timeProvider)

        val initialPackages = (1..1000).map { "com.blocked.app$it" }
        engine.syncBlockedApps(initialPackages)

        val threadCount = 14
        val readerThreads = 8
        val writerThreads = 4
        val unlockThreads = 2
        val evaluationsPerReader = 15_000
        val syncsPerWriter = 100

        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        val errors = ConcurrentLinkedQueue<Throwable>()
        val totalEvaluations = AtomicInteger(0)
        val running = AtomicBoolean(true)

        for (r in 0 until readerThreads) {
            executor.submit {
                try {
                    startLatch.await()
                    for (i in 0 until evaluationsPerReader) {
                        val pkg = if (i % 2 == 0) "com.blocked.app${(i % 1000) + 1}" else "com.other.app$i"
                        val decision = engine.evaluate(pkg)
                        if (decision.packageName.isBlank() && pkg.isNotBlank()) {
                            errors.add(IllegalStateException("Empty package returned for non-empty input"))
                        }
                        totalEvaluations.incrementAndGet()
                    }
                } catch (t: Throwable) {
                    errors.add(t)
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        for (w in 0 until writerThreads) {
            val writerId = w
            executor.submit {
                try {
                    startLatch.await()
                    for (s in 0 until syncsPerWriter) {
                        val offset = (writerId * 100) + s
                        val updatedList = (1..800).map { "com.blocked.app${it + offset}" }
                        engine.syncBlockedApps(updatedList)
                    }
                } catch (t: Throwable) {
                    errors.add(t)
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        for (u in 0 until unlockThreads) {
            val unlockId = u
            executor.submit {
                try {
                    startLatch.await()
                    var step = 0
                    while (running.get() && step < 500) {
                        step++
                        val pkg = "com.blocked.app${(step % 100) + (unlockId * 100) + 1}"
                        engine.registerTemporaryUnlock(pkg, durationSeconds = 10)
                        timeProvider.advance(50L)
                        engine.isTemporaryUnlockActive(pkg)
                        if (step % 10 == 0) {
                            engine.clearExpiredUnlocks()
                        }
                    }
                } catch (t: Throwable) {
                    errors.add(t)
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        val finished = doneLatch.await(15, TimeUnit.SECONDS)
        running.set(false)
        executor.shutdownNow()

        assertTrue("Execution timed out", finished)
        assertTrue("Unexpected errors encountered: $errors", errors.isEmpty())
        assertEquals(readerThreads * evaluationsPerReader, totalEvaluations.get())
    }

    @Test
    fun debounceFilterContentionEnsuresSingleWinner() {
        val timeProvider = FakeTimeProvider(1_000_000L)
        val filter = DebounceFilter(thresholdMs = 1500L, timeProvider = timeProvider)

        val threadCount = 16
        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        val winners = AtomicInteger(0)

        for (i in 0 until threadCount) {
            executor.submit {
                try {
                    startLatch.await()
                    if (filter.shouldProceed("com.burst.app")) {
                        winners.incrementAndGet()
                    }
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        assertTrue(doneLatch.await(5, TimeUnit.SECONDS))
        executor.shutdownNow()

        assertEquals(1, winners.get())
        assertEquals("com.burst.app", filter.getLastBlockedPackage())
        assertEquals(1_000_000L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun debounceFilterClockTamperingGuardRecovers() {
        val timeProvider = FakeTimeProvider(10_000L)
        val filter = DebounceFilter(thresholdMs = 1500L, timeProvider = timeProvider)

        assertTrue(filter.shouldProceed("com.app.target"))
        timeProvider.nowMs = 11_000L
        assertFalse(filter.shouldProceed("com.app.target"))

        timeProvider.nowMs = 5_000L
        assertTrue(filter.shouldProceed("com.app.target"))
        assertEquals(5_000L, filter.getLastBlockedTimeMs())
    }
}

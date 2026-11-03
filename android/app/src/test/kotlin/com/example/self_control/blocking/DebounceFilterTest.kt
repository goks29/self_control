package com.example.self_control.blocking

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DebounceFilterTest {
    private lateinit var fakeTime: FakeTimeProvider
    private lateinit var filter: DebounceFilter

    @Before
    fun setup() {
        fakeTime = FakeTimeProvider(5_000_000L)
        filter = DebounceFilter(thresholdMs = 1500L, timeProvider = fakeTime)
    }

    @Test
    fun defaultThresholdIs400ms() {
        assertEquals(400L, DebounceFilter.DEFAULT_THRESHOLD_MS)
    }

    @Test
    fun blankPackageReturnsFalse() {
        assertFalse(filter.shouldProceed(""))
        assertFalse(filter.shouldProceed("   "))
        assertNull(filter.getLastBlockedPackage())
    }

    @Test
    fun firstEventAlwaysProceeds() {
        assertTrue(filter.shouldProceed("com.example.app"))
        assertEquals("com.example.app", filter.getLastBlockedPackage())
        assertEquals(5_000_000L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun samePackageWithin1500msIsSuppressed() {
        assertTrue(filter.shouldProceed("com.example.app"))

        fakeTime.advance(500L)
        assertFalse(filter.shouldProceed("com.example.app"))

        fakeTime.advance(999L)
        assertFalse(filter.shouldProceed("com.example.app"))
    }

    @Test
    fun samePackageAfter1500msProceeds() {
        assertTrue(filter.shouldProceed("com.example.app"))

        fakeTime.advance(1500L)
        assertTrue(filter.shouldProceed("com.example.app"))
        assertEquals(5_001_500L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun differentPackageProceedsImmediately() {
        assertTrue(filter.shouldProceed("com.first.app"))

        fakeTime.advance(100L)
        assertTrue(filter.shouldProceed("com.second.app"))
        assertEquals("com.second.app", filter.getLastBlockedPackage())

        fakeTime.advance(100L)
        assertTrue(filter.shouldProceed("com.first.app"))
        assertEquals("com.first.app", filter.getLastBlockedPackage())
    }

    @Test
    fun clockTamperingBackwardRecoversAndProceeds() {
        assertTrue(filter.shouldProceed("com.example.app"))
        assertEquals(5_000_000L, filter.getLastBlockedTimeMs())

        fakeTime.advance(-200_000L)
        assertTrue(filter.shouldProceed("com.example.app"))
        assertEquals(4_800_000L, filter.getLastBlockedTimeMs())
    }

    @Test
    fun resetClearsState() {
        assertTrue(filter.shouldProceed("com.example.app"))
        filter.reset()
        assertNull(filter.getLastBlockedPackage())
        assertEquals(0L, filter.getLastBlockedTimeMs())
    }
}

package com.example.self_control.recovery

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import com.example.self_control.accessibility.LockScreenLauncher
import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.DebounceFilter
import com.example.self_control.blocking.FakeTimeProvider
import com.example.self_control.persistence.SessionData
import com.example.self_control.persistence.SharedPreferencesBlockingStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class Stage5ResilienceAdversarialTest {

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
        BootRecoveryController.reset()
    }

    @Test
    fun serviceRestartAfterLowMemoryKillRestoresAllState() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        store.saveBlockedPackages(setOf("com.instagram.android", "com.tiktok.android", "com.twitter.android"))
        store.saveActiveSession(
            startEpochMs = 900_000L,
            endEpochMs = 1_500_000L,
            status = "active"
        )
        store.saveTemporaryUnlock("com.instagram.android", expirationMs = 1_200_000L)
        store.saveTemporaryUnlock("com.tiktok.android", expirationMs = 950_000L)

        val restoredCount = BootRecoveryController.restoreFromPersistentStore(
            persistenceStore = store,
            blockingEngine = engine,
            timeProvider = fakeTime
        )

        assertEquals(3, restoredCount)
        assertTrue(engine.getBlockedPackages().contains("com.instagram.android"))
        assertTrue(engine.getBlockedPackages().contains("com.tiktok.android"))
        assertTrue(engine.getBlockedPackages().contains("com.twitter.android"))
        assertTrue(engine.isStrictSessionActive)

        assertTrue(engine.isTemporaryUnlockActive("com.instagram.android"))
        assertFalse(engine.isTemporaryUnlockActive("com.tiktok.android"))

        val instagramDecision = engine.evaluate("com.instagram.android")
        assertFalse(instagramDecision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, instagramDecision.reason)

        val tiktokDecision = engine.evaluate("com.tiktok.android")
        assertTrue(tiktokDecision.shouldBlock)

        val twitterDecision = engine.evaluate("com.twitter.android")
        assertTrue(twitterDecision.shouldBlock)
    }

    @Test
    fun serviceRestartWhenActiveSessionElapsedMarksSessionCompleted() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        store.saveBlockedPackages(setOf("com.facebook.katana"))
        store.saveActiveSession(
            startEpochMs = 800_000L,
            endEpochMs = 999_999L,
            status = "active"
        )

        BootRecoveryController.restoreFromPersistentStore(
            persistenceStore = store,
            blockingEngine = engine,
            timeProvider = fakeTime
        )

        assertFalse(engine.isStrictSessionActive)
        val updatedSession = store.getActiveSession()
        assertNotNull(updatedSession)
        assertEquals("completed", updatedSession?.status)
    }

    @Test
    fun batteryLowAndPowerSaveModePurgesExpiredUnlocks() {
        engine.syncBlockedApps(setOf("com.tiktok.android"))
        engine.registerTemporaryUnlock("com.tiktok.android", 100, 1_000_500L)

        assertTrue(engine.isTemporaryUnlockActive("com.tiktok.android"))

        fakeTime.advance(600L)
        assertEquals(1_000_600L, fakeTime.currentTimeMillis())

        engine.clearExpiredUnlocks(fakeTime.currentTimeMillis())

        assertFalse(engine.isTemporaryUnlockActive("com.tiktok.android"))
        val decision = engine.evaluate("com.tiktok.android")
        assertTrue(decision.shouldBlock)
    }

    @Test
    fun sharedPreferencesConcurrentWritesNoDataLossWithinCapacity() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        val threadCount = 10
        val writesPerThread = 15
        val totalWrites = threadCount * writesPerThread
        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        val errors = ConcurrentLinkedQueue<Throwable>()

        for (t in 0 until threadCount) {
            val threadId = t
            executor.submit {
                try {
                    startLatch.await()
                    for (i in 0 until writesPerThread) {
                        store.recordPendingActivityLog(
                            packageName = "com.test.app$threadId",
                            outcome = if (i % 2 == 0) "confirmed" else "failed",
                            details = "attempt_$i",
                            timestampMs = 1_000_000L + (threadId * 100) + i
                        )
                    }
                } catch (err: Throwable) {
                    errors.add(err)
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        val completed = doneLatch.await(5, TimeUnit.SECONDS)
        executor.shutdownNow()

        assertTrue(completed)
        assertTrue(errors.isEmpty())

        val logs = store.consumePendingActivityLogs()
        assertEquals(totalWrites, logs.size)

        val drainedAgain = store.consumePendingActivityLogs()
        assertTrue(drainedAgain.isEmpty())
    }

    @Test
    fun sharedPreferencesBufferCapTrimsOldestLogsWithoutCorruption() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        for (i in 1..250) {
            store.recordPendingActivityLog(
                packageName = "com.app.item$i",
                outcome = "confirmed",
                details = "index_$i",
                timestampMs = 1_000_000L + i
            )
        }

        val logs = store.consumePendingActivityLogs()
        assertEquals(SharedPreferencesBlockingStore.MAX_PENDING_LOGS, logs.size)

        assertEquals("com.app.item51", logs.first()["packageName"])
        assertEquals("index_51", logs.first()["details"])
        assertEquals("com.app.item250", logs.last()["packageName"])
        assertEquals("index_250", logs.last()["details"])
    }

    @Test
    fun lockScreenLauncherDebounceSuppressesDuplicateLaunches() {
        val memoryPrefs = InMemorySharedPreferences()
        val dummyContext = createTestContext(memoryPrefs)

        val decision = BlockingDecision.Block(
            packageName = "com.instagram.android",
            timestamp = 1_000_000L,
            reason = BlockingDecision.Block.REASON_POLICY_RESTRICTED
        )

        val launchedFirst = LockScreenLauncher.launchLockScreen(dummyContext, decision, engine)
        assertTrue(launchedFirst)
        assertEquals(BlockingDecision.Block.STATUS_CONFIRMED, engine.lastEvaluationResult)

        fakeTime.advance(500L)
        val launchedSecond = LockScreenLauncher.launchLockScreen(
            dummyContext,
            decision.copy(timestamp = 1_000_500L),
            engine
        )
        assertFalse(launchedSecond)
    }

    @Test
    fun lockScreenLauncherRecordsFailureWhenStartActivityThrows() {
        val memoryPrefs = InMemorySharedPreferences()
        val failingContext = createFailingTestContext(
            memoryPrefs,
            ActivityNotFoundException("No activity found for intent")
        )

        val decision = BlockingDecision.Block(
            packageName = "com.broken.target",
            timestamp = 1_000_000L,
            reason = BlockingDecision.Block.REASON_POLICY_RESTRICTED
        )

        val launched = LockScreenLauncher.launchLockScreen(failingContext, decision, engine)
        assertFalse(launched)
        assertEquals(BlockingDecision.Block.STATUS_FAILED, engine.lastEvaluationResult)

        val store = SharedPreferencesBlockingStore(memoryPrefs)
        val logs = store.consumePendingActivityLogs()
        assertEquals(1, logs.size)
        assertEquals("com.broken.target", logs[0]["packageName"])
        assertEquals(BlockingDecision.Block.STATUS_FAILED, logs[0]["outcome"])
        assertTrue((logs[0]["details"] as String).contains("ActivityNotFoundException"))
    }

    private fun createTestContext(prefs: SharedPreferences): Context {
        return object : ContextWrapper(null) {
            override fun getApplicationContext(): Context = this
            override fun getPackageName(): String = "com.example.self_control"
            override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
            override fun startActivity(intent: Intent?) {}
            override fun startActivity(intent: Intent?, options: Bundle?) {}
        }
    }

    private fun createFailingTestContext(prefs: SharedPreferences, error: RuntimeException): Context {
        return object : ContextWrapper(null) {
            override fun getApplicationContext(): Context = this
            override fun getPackageName(): String = "com.example.self_control"
            override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = prefs
            override fun startActivity(intent: Intent?) {
                throw error
            }
            override fun startActivity(intent: Intent?, options: Bundle?) {
                throw error
            }
        }
    }

    private class InMemorySharedPreferences : SharedPreferences {
        val map = ConcurrentHashMap<String, Any>()

        override fun getAll(): Map<String, *> = HashMap(map)

        override fun getString(key: String?, defValue: String?): String? {
            val v = map[key] ?: return defValue
            if (v !is String) throw ClassCastException("Value $v is not String")
            return v
        }

        override fun getStringSet(key: String?, defValues: Set<String>?): Set<String>? {
            val v = map[key] ?: return defValues
            if (v !is Set<*>) throw ClassCastException("Value $v is not Set")
            @Suppress("UNCHECKED_CAST")
            return (v as Set<String>).toSet()
        }

        override fun getInt(key: String?, defValue: Int): Int {
            val v = map[key] ?: return defValue
            if (v !is Int) throw ClassCastException("Value $v is not Int")
            return v
        }

        override fun getLong(key: String?, defValue: Long): Long {
            val v = map[key] ?: return defValue
            if (v !is Long) throw ClassCastException("Value $v is not Long")
            return v
        }

        override fun getFloat(key: String?, defValue: Float): Float {
            val v = map[key] ?: return defValue
            if (v !is Float) throw ClassCastException("Value $v is not Float")
            return v
        }

        override fun getBoolean(key: String?, defValue: Boolean): Boolean {
            val v = map[key] ?: return defValue
            if (v !is Boolean) throw ClassCastException("Value $v is not Boolean")
            return v
        }

        override fun contains(key: String?): Boolean = map.containsKey(key)

        override fun edit(): SharedPreferences.Editor = EditorImpl(this)

        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}

        class EditorImpl(private val prefs: InMemorySharedPreferences) : SharedPreferences.Editor {
            private val modifications = HashMap<String, Any?>()
            private var shouldClear = false

            override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                if (key != null) modifications[key] = value
                return this
            }

            override fun putStringSet(key: String?, values: Set<String>?): SharedPreferences.Editor {
                if (key != null) modifications[key] = values?.toSet()
                return this
            }

            override fun putInt(key: String?, value: Int): SharedPreferences.Editor {
                if (key != null) modifications[key] = value
                return this
            }

            override fun putLong(key: String?, value: Long): SharedPreferences.Editor {
                if (key != null) modifications[key] = value
                return this
            }

            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor {
                if (key != null) modifications[key] = value
                return this
            }

            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor {
                if (key != null) modifications[key] = value
                return this
            }

            override fun remove(key: String?): SharedPreferences.Editor {
                if (key != null) modifications[key] = this
                return this
            }

            override fun clear(): SharedPreferences.Editor {
                shouldClear = true
                return this
            }

            override fun commit(): Boolean {
                apply()
                return true
            }

            override fun apply() {
                synchronized(prefs) {
                    if (shouldClear) {
                        prefs.map.clear()
                    }
                    for ((k, v) in modifications) {
                        if (v === this || v == null) {
                            prefs.map.remove(k)
                        } else {
                            prefs.map[k] = v
                        }
                    }
                }
            }
        }
    }
}

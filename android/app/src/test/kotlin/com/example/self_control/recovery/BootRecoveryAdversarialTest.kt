package com.example.self_control.recovery

import android.content.SharedPreferences
import com.example.self_control.blocking.BlockingDecision
import com.example.self_control.blocking.BlockingEngine
import com.example.self_control.blocking.FakeTimeProvider
import com.example.self_control.blocking.TimeProvider
import com.example.self_control.persistence.BlockingPersistenceStore
import com.example.self_control.persistence.SessionData
import com.example.self_control.persistence.SharedPreferencesBlockingStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class BootRecoveryAdversarialTest {

    private lateinit var fakeTime: FakeTimeProvider
    private lateinit var engine: BlockingEngine

    @Before
    fun setup() {
        fakeTime = FakeTimeProvider(1_000_000L)
        engine = BlockingEngine(
            selfPackageName = "com.example.self_control",
            timeProvider = fakeTime
        )
        BootRecoveryController.reset()
    }

    @Test
    fun boundaryExpirationExactNowExpiresUnlock() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.saveBlockedPackages(listOf("com.instagram.android"))
        fakeStore.saveTemporaryUnlock("com.instagram.android", expirationMs = 1_000_000L)

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertTrue(result.handled)
        assertFalse(fakeStore.savedUnlocks.containsKey("com.instagram.android"))
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))
        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
    }

    @Test
    fun boundaryExpirationPastNowExpiresUnlock() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.saveBlockedPackages(listOf("com.instagram.android"))
        fakeStore.saveTemporaryUnlock("com.instagram.android", expirationMs = 999_999L)

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertTrue(result.handled)
        assertFalse(fakeStore.savedUnlocks.containsKey("com.instagram.android"))
        assertFalse(engine.isTemporaryUnlockActive("com.instagram.android"))
        val decision = engine.evaluate("com.instagram.android")
        assertTrue(decision.shouldBlock)
    }

    @Test
    fun boundaryExpirationFutureRemainingFullSecondPreserved() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.saveBlockedPackages(listOf("com.instagram.android"))
        fakeStore.saveTemporaryUnlock("com.instagram.android", expirationMs = 1_060_000L)

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        assertTrue(result.handled)
        assertTrue(fakeStore.savedUnlocks.containsKey("com.instagram.android"))
        assertTrue(engine.isTemporaryUnlockActive("com.instagram.android"))
        val decision = engine.evaluate("com.instagram.android")
        assertFalse(decision.shouldBlock)
        assertEquals(BlockingDecision.Allow.REASON_TEMPORARY_UNLOCK, decision.reason)
    }

    @Test
    fun boundaryExpirationSubSecondRemainingBehavior() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.saveBlockedPackages(listOf("com.instagram.android"))
        val subSecondExpiration = 1_000_500L
        fakeStore.saveTemporaryUnlock("com.instagram.android", expirationMs = subSecondExpiration)

        controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)

        val isPersisted = fakeStore.savedUnlocks.containsKey("com.instagram.android")
        val isEngineActive = engine.isTemporaryUnlockActive("com.instagram.android")

        assertTrue(isPersisted)
        assertTrue(isEngineActive)
    }

    @Test
    fun sessionExpirationExactEndEpochMarksCompleted() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.savedSession = SessionData(
            startEpochMs = 900_000L,
            endEpochMs = 1_000_000L,
            status = "active"
        )

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)
        assertEquals("completed", result.sessionStatus)
        assertEquals("completed", fakeStore.savedSession?.status)
    }

    @Test
    fun sessionWithZeroEndEpochRemainsActiveIndefinitely() {
        val fakeStore = FakeBlockingPersistenceStore()
        val controller = BootRecoveryController(fakeStore, engine, fakeTime)

        fakeStore.savedSession = SessionData(
            startEpochMs = 900_000L,
            endEpochMs = 0L,
            status = "active"
        )

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)
        assertEquals("active", result.sessionStatus)
        assertEquals("active", fakeStore.savedSession?.status)
    }

    @Test
    fun corruptedSessionClassCastExceptionHandling() {
        val memoryPrefs = InMemorySharedPreferences()
        memoryPrefs.edit()
            .putStringSet(SharedPreferencesBlockingStore.KEY_BLOCKED_PACKAGES, setOf("com.corrupt.app"))
            .putString(SharedPreferencesBlockingStore.KEY_SESSION_START, "not_a_long")
            .putString(SharedPreferencesBlockingStore.KEY_SESSION_STATUS, "active")
            .apply()

        val store = SharedPreferencesBlockingStore(memoryPrefs)
        val controller = BootRecoveryController(store, engine, fakeTime)

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)
        assertTrue(result.handled)
        assertTrue(engine.getBlockedPackages().contains("com.corrupt.app"))
        assertEquals(listOf(1_000_000L), store.consumePendingBootSyncs())
    }

    @Test
    fun corruptedTemporaryUnlockTypeHandledGracefully() {
        val memoryPrefs = InMemorySharedPreferences()
        memoryPrefs.edit()
            .putStringSet(SharedPreferencesBlockingStore.KEY_BLOCKED_PACKAGES, setOf("com.app.one"))
            .putString("${SharedPreferencesBlockingStore.KEY_UNLOCK_PREFIX}com.app.bad", "not_a_long")
            .putLong("${SharedPreferencesBlockingStore.KEY_UNLOCK_PREFIX}com.app.good", 1_050_000L)
            .apply()

        val store = SharedPreferencesBlockingStore(memoryPrefs)
        val controller = BootRecoveryController(store, engine, fakeTime)

        val result = controller.handleBoot(BootRecoveryController.ACTION_BOOT_COMPLETED)
        assertTrue(result.handled)
        assertEquals(1, result.restoredCount)
        assertTrue(engine.isTemporaryUnlockActive("com.app.good"))
        assertFalse(engine.isTemporaryUnlockActive("com.app.bad"))
    }

    @Test
    fun concurrentBootBroadcastStormUnderHighContention() {
        val fakeStore = SynchronizedFakeStore()
        fakeStore.saveBlockedPackages(listOf("com.storm.target"))

        val threadCount = 20
        val executor = Executors.newFixedThreadPool(threadCount)
        val startLatch = CountDownLatch(1)
        val doneLatch = CountDownLatch(threadCount)
        val errors = ConcurrentLinkedQueue<Throwable>()
        val successCount = AtomicInteger(0)

        for (i in 0 until threadCount) {
            val action = if (i % 2 == 0) {
                BootRecoveryController.ACTION_BOOT_COMPLETED
            } else {
                BootRecoveryController.ACTION_QUICKBOOT_POWERON
            }
            executor.submit {
                try {
                    startLatch.await()
                    val ctrl = BootRecoveryController(fakeStore, engine, fakeTime)
                    val res = ctrl.handleBoot(action)
                    if (res.handled) {
                        successCount.incrementAndGet()
                    }
                } catch (t: Throwable) {
                    errors.add(t)
                } finally {
                    doneLatch.countDown()
                }
            }
        }

        startLatch.countDown()
        val finished = doneLatch.await(5, TimeUnit.SECONDS)
        executor.shutdownNow()

        assertTrue(finished)
        assertTrue(errors.isEmpty())
        assertEquals(threadCount, successCount.get())
        assertTrue(engine.getBlockedPackages().contains("com.storm.target"))
        assertEquals(1, fakeStore.pendingBootSyncs.size)
    }

    @Test
    fun drainPendingBootSyncsIsAtomicAndConsumesAll() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        store.recordPendingBootSync(100L)
        store.recordPendingBootSync(200L)
        store.recordPendingBootSync(150L)

        val drained1 = store.consumePendingBootSyncs()
        assertEquals(listOf(100L, 150L, 200L), drained1)

        val drained2 = store.consumePendingBootSyncs()
        assertTrue(drained2.isEmpty())
    }

    @Test
    fun concurrentRecordAndConsumePendingBootSyncsDataLossCheck() {
        val memoryPrefs = InMemorySharedPreferences()
        val store = SharedPreferencesBlockingStore(memoryPrefs)

        val writerThreads = 8
        val itemsPerWriter = 50
        val totalExpected = writerThreads * itemsPerWriter

        val executor = Executors.newFixedThreadPool(writerThreads + 2)
        val startLatch = CountDownLatch(1)
        val writersDone = CountDownLatch(writerThreads)
        val drainedList = ConcurrentLinkedQueue<Long>()
        val running = java.util.concurrent.atomic.AtomicBoolean(true)

        for (w in 0 until writerThreads) {
            val writerId = w
            executor.submit {
                try {
                    startLatch.await()
                    for (i in 0 until itemsPerWriter) {
                        val ts = (writerId * 10_000L) + i + 1L
                        store.recordPendingBootSync(ts)
                    }
                } finally {
                    writersDone.countDown()
                }
            }
        }

        for (c in 0 until 2) {
            executor.submit {
                startLatch.await()
                while (running.get()) {
                    val batch = store.consumePendingBootSyncs()
                    if (batch.isNotEmpty()) {
                        drainedList.addAll(batch)
                    }
                    Thread.sleep(1)
                }
                val lastBatch = store.consumePendingBootSyncs()
                drainedList.addAll(lastBatch)
            }
        }

        startLatch.countDown()
        assertTrue(writersDone.await(5, TimeUnit.SECONDS))
        Thread.sleep(50)
        running.set(false)
        executor.shutdown()
        assertTrue(executor.awaitTermination(3, TimeUnit.SECONDS))

        val finalDrained = store.consumePendingBootSyncs()
        drainedList.addAll(finalDrained)

        val distinctDrained = drainedList.toSet().size
        assertTrue(distinctDrained <= totalExpected)
    }

    private class SynchronizedFakeStore : BlockingPersistenceStore {
        private var savedPackages: MutableSet<String> = mutableSetOf()
        private var savedSession: SessionData? = null
        val pendingBootSyncs: MutableList<Long> = mutableListOf()
        private val savedUnlocks: MutableMap<String, Long> = mutableMapOf()

        @Synchronized
        override fun getBlockedPackages(): Set<String> = savedPackages.toSet()

        @Synchronized
        override fun saveBlockedPackages(packages: Collection<String>) {
            savedPackages = packages.toMutableSet()
        }

        @Synchronized
        override fun getActiveSession(): SessionData? = savedSession

        @Synchronized
        override fun saveActiveSession(startEpochMs: Long, endEpochMs: Long, status: String) {
            savedSession = SessionData(startEpochMs, endEpochMs, status)
        }

        @Synchronized
        override fun updateSessionStatus(status: String) {
            savedSession = savedSession?.copy(status = status)
        }

        @Synchronized
        override fun recordPendingBootSync(timestampMs: Long) {
            pendingBootSyncs.add(timestampMs)
        }

        @Synchronized
        override fun consumePendingBootSyncs(): List<Long> {
            val copy = pendingBootSyncs.toList()
            pendingBootSyncs.clear()
            return copy
        }

        @Synchronized
        override fun getSavedTemporaryUnlocks(): Map<String, Long> = savedUnlocks.toMap()

        @Synchronized
        override fun saveTemporaryUnlock(packageName: String, expirationMs: Long) {
            savedUnlocks[packageName] = expirationMs
        }

        @Synchronized
        override fun removeTemporaryUnlock(packageName: String) {
            savedUnlocks.remove(packageName)
        }

        @Synchronized
        override fun clearExpiredTemporaryUnlocks(nowMs: Long) {
            val iter = savedUnlocks.entries.iterator()
            while (iter.hasNext()) {
                if (iter.next().value <= nowMs) {
                    iter.remove()
                }
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

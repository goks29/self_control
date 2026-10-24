package com.example.self_control.blocking

import java.util.concurrent.atomic.AtomicReference

class DebounceFilter(
    private val thresholdMs: Long = DEFAULT_THRESHOLD_MS,
    private val timeProvider: TimeProvider = SystemTimeProvider
) {
    companion object {
        const val DEFAULT_THRESHOLD_MS = 1500L
    }

    private data class State(
        val lastPackage: String?,
        val lastTimestampMs: Long
    )

    private val stateRef = AtomicReference(State(null, 0L))

    fun shouldProceed(packageName: String): Boolean {
        if (packageName.isBlank()) return false
        val now = timeProvider.currentTimeMillis()

        while (true) {
            val current = stateRef.get()
            val elapsed = now - current.lastTimestampMs

            if (packageName == current.lastPackage && elapsed in 0 until thresholdMs) {
                return false
            }

            val next = State(lastPackage = packageName, lastTimestampMs = now)
            if (stateRef.compareAndSet(current, next)) {
                return true
            }
        }
    }

    fun getLastBlockedPackage(): String? = stateRef.get().lastPackage

    fun getLastBlockedTimeMs(): Long = stateRef.get().lastTimestampMs

    fun reset() {
        stateRef.set(State(null, 0L))
    }
}

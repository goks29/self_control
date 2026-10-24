package com.example.self_control.blocking

class FakeTimeProvider(var nowMs: Long = 1_000_000L) : TimeProvider {
    override fun currentTimeMillis(): Long = nowMs
    fun advance(deltaMs: Long) {
        nowMs += deltaMs
    }
}

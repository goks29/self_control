package com.example.self_control.platform

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.Proxy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BlockingMethodHandlerReadFailureTest {
    private class TestResult : MethodChannel.Result {
        var successCount = 0
        var errorCount = 0
        var successValue: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null

        override fun success(result: Any?) {
            successCount++
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorCount++
            this.errorCode = errorCode
            this.errorMessage = errorMessage
            assertNull(errorDetails)
        }

        override fun notImplemented() {
            throw AssertionError("Read method must be implemented")
        }
    }

    private class PreferencesContext(
        private val preferences: () -> SharedPreferences
    ) : ContextWrapper(null) {
        override fun getApplicationContext(): Context = this

        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = preferences()
    }

    private fun assertReadFailure(method: String, expectedCode: String) {
        val handler = BlockingMethodHandler(context = PreferencesContext {
            throw IllegalStateException("Preferences unavailable")
        })
        try {
            val result = TestResult()
            handler.onMethodCall(MethodCall(method, null), result)
            assertEquals(0, result.successCount)
            assertEquals(1, result.errorCount)
            assertEquals(expectedCode, result.errorCode)
            assertEquals("Preferences unavailable", result.errorMessage)
        } finally {
            handler.release()
        }
    }

    @Test
    fun pendingBootReadFailureIsNotSuccessfulEmptyData() {
        assertReadFailure("consumePendingBootEvents", "CONSUME_BOOT_EVENTS_FAILED")
    }

    @Test
    fun legacyPendingBootReadAliasAlsoReportsFailure() {
        assertReadFailure("getPendingBootSyncs", "CONSUME_BOOT_EVENTS_FAILED")
    }

    @Test
    fun pendingActivityReadFailureIsNotSuccessfulEmptyData() {
        assertReadFailure("consumePendingActivityLogs", "CONSUME_ACTIVITY_LOGS_FAILED")
    }

    @Test
    fun successfulEmptyPendingReadsRemainSuccessful() {
        val preferences = Proxy.newProxyInstance(
            SharedPreferences::class.java.classLoader,
            arrayOf(SharedPreferences::class.java)
        ) { _, method, args ->
            when (method.name) {
                "getString", "getStringSet" -> args!![1]
                else -> throw AssertionError("Unexpected preference operation: ${method.name}")
            }
        } as SharedPreferences
        val handler = BlockingMethodHandler(context = PreferencesContext { preferences })
        try {
            for (method in listOf(
                "consumePendingBootEvents", "getPendingBootSyncs", "consumePendingActivityLogs"
            )) {
                val result = TestResult()
                handler.onMethodCall(MethodCall(method, null), result)
                assertEquals(method, 1, result.successCount)
                assertEquals(method, emptyList<Any>(), result.successValue)
                assertEquals(method, 0, result.errorCount)
            }
        } finally {
            handler.release()
        }
    }
}

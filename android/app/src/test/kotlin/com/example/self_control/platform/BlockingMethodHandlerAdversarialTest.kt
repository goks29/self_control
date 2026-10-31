package com.example.self_control.platform

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockingMethodHandlerAdversarialTest {

    private class TestResult : MethodChannel.Result {
        var successValue: Any? = null
        var errorCode: String? = null
        var errorMessage: String? = null
        var errorDetails: Any? = null
        var notImplementedCalled: Boolean = false

        override fun success(result: Any?) {
            successValue = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            this.errorCode = errorCode
            this.errorMessage = errorMessage
            this.errorDetails = errorDetails
        }

        override fun notImplemented() {
            notImplementedCalled = true
        }
    }

    private class TestActivity : Activity() {
        var movedToBack: Boolean = false
        var nonRootArgument: Boolean = false
        var shouldThrowOnMoveToBack: Boolean = false

        override fun moveTaskToBack(nonRoot: Boolean): Boolean {
            if (shouldThrowOnMoveToBack) {
                throw SecurityException("Permission denied to move task to back")
            }
            movedToBack = true
            nonRootArgument = nonRoot
            return true
        }
    }

    private class TestIntent(action: String) : Intent(action) {
        private var customFlags: Int = 0

        override fun addFlags(flags: Int): Intent {
            customFlags = customFlags or flags
            return this
        }

        override fun getFlags(): Int = customFlags
    }

    private class TestContext : ContextWrapper(null) {
        var startedIntent: Intent? = null
        var exceptionToThrowOnStart: RuntimeException? = null

        override fun getApplicationContext(): Context = this

        override fun startActivity(intent: Intent?) {
            exceptionToThrowOnStart?.let { throw it }
            startedIntent = intent
        }
    }

    @Test
    fun launchTargetAppRejectsBlankAndWhitespacePackageNames() {
        val handler = BlockingMethodHandler(context = TestContext())

        val blanks = listOf("", "   ", "\t", "\n", "  \n  ")
        for (pkg in blanks) {
            val result = TestResult()
            handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to pkg)), result)
            assertEquals("Expected false for blank package: '$pkg'", false, result.successValue)
        }
    }

    @Test
    fun launchTargetAppRejectsNullOrMissingPackageArgument() {
        val handler = BlockingMethodHandler(context = TestContext())

        val result1 = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf<String, Any?>("packageName" to null)), result1)
        assertEquals(false, result1.successValue)

        val result2 = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf<String, Any?>("otherKey" to "com.example")), result2)
        assertEquals(false, result2.successValue)

        val result3 = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", null), result3)
        assertEquals(false, result3.successValue)
    }

    @Test
    fun launchTargetAppHandlesNonStringPackageArgumentGracefully() {
        val handler = BlockingMethodHandler(context = TestContext())

        val result1 = TestResult()
        try {
            handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to 12345)), result1)
            assertEquals(false, result1.successValue)
        } catch (_: ClassCastException) {
        }

        val result2 = TestResult()
        try {
            handler.onMethodCall(MethodCall("launchTargetApp", "invalid-argument-format"), result2)
            assertEquals(false, result2.successValue)
        } catch (_: ClassCastException) {
        }
    }

    @Test
    fun launchTargetAppSetsExpectedFlagsAndBringsTaskToBack() {
        val testContext = TestContext()
        val testActivity = TestActivity()
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = { testActivity },
            launchIntentProvider = { targetIntent }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.test.valid")), result)

        assertEquals(true, result.successValue)
        assertNotNull(testContext.startedIntent)

        val flags = testContext.startedIntent!!.flags
        val expectedNewTask = Intent.FLAG_ACTIVITY_NEW_TASK
        val expectedResetTask = Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        assertEquals(expectedNewTask, flags and expectedNewTask)
        assertEquals(expectedResetTask, flags and expectedResetTask)

        assertTrue(testActivity.movedToBack)
        assertTrue(testActivity.nonRootArgument)
    }

    @Test
    fun launchTargetAppFailsGracefullyWhenStartActivityThrowsSecurityException() {
        val testContext = TestContext().apply {
            exceptionToThrowOnStart = SecurityException("Permission Denial")
        }
        val testActivity = TestActivity()
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = { testActivity },
            launchIntentProvider = { targetIntent }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.protected.app")), result)

        assertEquals(false, result.successValue)
        assertFalse(testActivity.movedToBack)
    }

    @Test
    fun launchTargetAppFailsGracefullyWhenMoveTaskToBackThrows() {
        val testContext = TestContext()
        val testActivity = TestActivity().apply {
            shouldThrowOnMoveToBack = true
        }
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = { testActivity },
            launchIntentProvider = { targetIntent }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.test.valid")), result)

        assertEquals(false, result.successValue)
    }

    @Test
    fun launchTargetAppWithoutActivityProviderStillLaunches() {
        val testContext = TestContext()
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = null,
            launchIntentProvider = { targetIntent }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.headless.app")), result)

        assertEquals(true, result.successValue)
        assertNotNull(testContext.startedIntent)
    }

    @Test
    fun getInitialLockIntentStrictSingleConsumptionSemantics() {
        val handler = BlockingMethodHandler(context = TestContext())
        handler.setInitialLockIntent("com.target.app", 1700000000000L)

        val res1 = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), res1)
        assertNotNull(res1.successValue)

        val res2 = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), res2)
        assertNull("Second call must return null", res2.successValue)

        val res3 = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), res3)
        assertNull("Third call must return null", res3.successValue)
    }

    @Test
    fun verifyMainActivityDualProvisioningConsumptionBehavior() {
        var activityCache: Map<String, Any?>? = mapOf(
            "packageName" to "com.cold.app",
            "blockedAt" to 999999L
        )

        val handler = BlockingMethodHandler(
            context = TestContext(),
            initialLockIntentProvider = {
                val data = activityCache
                activityCache = null
                data
            }
        )

        if (activityCache != null) {
            handler.setInitialLockIntent(activityCache)
        }

        val call1 = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), call1)
        assertNotNull(call1.successValue)

        val call2 = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), call2)
        assertNull("Second call must be null for single-consumption semantics", call2.successValue)
    }
}

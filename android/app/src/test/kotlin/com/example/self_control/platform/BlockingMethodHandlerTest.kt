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

class BlockingMethodHandlerTest {

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

        override fun moveTaskToBack(nonRoot: Boolean): Boolean {
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
        var shouldThrowOnStart: Boolean = false

        override fun getApplicationContext(): Context = this

        override fun startActivity(intent: Intent?) {
            if (shouldThrowOnStart) {
                throw ActivityNotFoundException("Activity not found")
            }
            startedIntent = intent
        }
    }

    @Test
    fun launchTargetAppRejectsEmptyPackageName() {
        val result = TestResult()
        val handler = BlockingMethodHandler(context = TestContext())
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "")), result)
        assertEquals(false, result.successValue)

        val nullResult = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf<String, Any?>()), nullResult)
        assertEquals(false, nullResult.successValue)
    }

    @Test
    fun launchTargetAppReturnsFalseWhenPackageHasNoIntent() {
        val result = TestResult()
        val handler = BlockingMethodHandler(
            context = TestContext(),
            launchIntentProvider = { null }
        )
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.unknown.app")), result)
        assertEquals(false, result.successValue)
    }

    @Test
    fun launchTargetAppLaunchesAndMinimizesActivity() {
        val testContext = TestContext()
        val testActivity = TestActivity()
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = { testActivity },
            launchIntentProvider = { pkg -> if (pkg == "com.instagram.android") targetIntent else null }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.instagram.android")), result)

        assertEquals(true, result.successValue)
        assertNotNull(testContext.startedIntent)
        val flags = testContext.startedIntent!!.flags
        assertTrue((flags and Intent.FLAG_ACTIVITY_NEW_TASK) != 0)
        assertTrue((flags and Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED) != 0)
        assertTrue(testActivity.movedToBack)
        assertTrue(testActivity.nonRootArgument)
    }

    @Test
    fun launchTargetAppReturnsFalseWhenStartActivityThrows() {
        val testContext = TestContext().apply { shouldThrowOnStart = true }
        val testActivity = TestActivity()
        val targetIntent = TestIntent("android.intent.action.MAIN")

        val handler = BlockingMethodHandler(
            context = testContext,
            activityProvider = { testActivity },
            launchIntentProvider = { targetIntent }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("launchTargetApp", mapOf("packageName" to "com.broken.app")), result)

        assertEquals(false, result.successValue)
        assertFalse(testActivity.movedToBack)
    }

    @Test
    fun getInitialLockIntentReturnsAndConsumesData() {
        val handler = BlockingMethodHandler(context = TestContext())
        handler.setInitialLockIntent("com.instagram.android", 1700000000000L)

        val firstResult = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), firstResult)

        @Suppress("UNCHECKED_CAST")
        val map = firstResult.successValue as? Map<String, Any?>
        assertNotNull(map)
        assertEquals("com.instagram.android", map?.get("packageName"))
        assertEquals(1700000000000L, map?.get("blockedAt"))

        val secondResult = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), secondResult)
        assertNull(secondResult.successValue)
    }

    @Test
    fun getInitialLockIntentConsumesFromProvider() {
        var providerData: Map<String, Any?>? = mapOf(
            "packageName" to "com.tiktok.android",
            "blockedAt" to 1600000000000L
        )

        val handler = BlockingMethodHandler(
            context = TestContext(),
            initialLockIntentProvider = {
                val data = providerData
                providerData = null
                data
            }
        )

        val firstResult = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), firstResult)

        @Suppress("UNCHECKED_CAST")
        val map = firstResult.successValue as? Map<String, Any?>
        assertNotNull(map)
        assertEquals("com.tiktok.android", map?.get("packageName"))

        val secondResult = TestResult()
        handler.onMethodCall(MethodCall("getInitialLockIntent", null), secondResult)
        assertNull(secondResult.successValue)
    }

    @Test
    fun minimizeLockScreenCallsMoveTaskToBack() {
        val testActivity = TestActivity()
        val handler = BlockingMethodHandler(
            context = TestContext(),
            activityProvider = { testActivity }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("minimizeLockScreen", null), result)

        assertEquals(true, result.successValue)
        assertTrue(testActivity.movedToBack)
        assertTrue(testActivity.nonRootArgument)
    }

    @Test
    fun minimizeLockScreenReturnsFalseWhenActivityNull() {
        val handler = BlockingMethodHandler(
            context = TestContext(),
            activityProvider = { null }
        )

        val result = TestResult()
        handler.onMethodCall(MethodCall("minimizeLockScreen", null), result)

        assertEquals(false, result.successValue)
    }
}

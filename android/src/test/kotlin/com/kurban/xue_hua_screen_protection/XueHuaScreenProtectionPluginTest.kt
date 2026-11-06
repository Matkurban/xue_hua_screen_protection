package com.kurban.xue_hua_screen_protection

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class XueHuaScreenProtectionPluginTest {
    @Test
    fun onMethodCall_setSecureScreen_returnsTrue() {
        val plugin = XueHuaScreenProtectionPlugin()

        val call = MethodCall("setSecureScreen", mapOf("enabled" to true))
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).success(true)
    }

    @Test
    fun onMethodCall_isSecureScreenEnabled_reflectsState() {
        val plugin = XueHuaScreenProtectionPlugin()

        val enableCall = MethodCall("setSecureScreen", mapOf("enabled" to true))
        val enableResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(enableCall, enableResult)

        val queryCall = MethodCall("isSecureScreenEnabled", null)
        val queryResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(queryCall, queryResult)

        Mockito.verify(queryResult).success(true)

        val disableCall = MethodCall("setSecureScreen", mapOf("enabled" to false))
        val disableResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(disableCall, disableResult)
        Mockito.verify(disableResult).success(true)

        val queryAfterDisableResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(queryCall, queryAfterDisableResult)
        Mockito.verify(queryAfterDisableResult).success(false)
    }

    @Test
    fun onMethodCall_configureAppSwitcherProtection_togglesMaskStatus() {
        val plugin = XueHuaScreenProtectionPlugin()

        val enableMaskCall = MethodCall(
            "configureAppSwitcherProtection",
            mapOf("enabled" to true, "style" to "blur")
        )
        val enableMaskResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(enableMaskCall, enableMaskResult)
        Mockito.verify(enableMaskResult).success(true)

        val statusCall = MethodCall("getProtectionStatus", null)
        val statusEnabledResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(statusCall, statusEnabledResult)
        Mockito.verify(statusEnabledResult).success(
            mapOf(
                "isSecureScreenEnabled" to false,
                "isAppSwitcherMaskEnabled" to true,
                "isScreenBeingRecorded" to false,
                "isMaskCurrentlyVisible" to false,
                "platform" to "android"
            )
        )

        val disableMaskCall = MethodCall(
            "configureAppSwitcherProtection",
            mapOf("enabled" to false, "style" to "none")
        )
        val disableMaskResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(disableMaskCall, disableMaskResult)
        Mockito.verify(disableMaskResult).success(true)

        val statusDisabledResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(statusCall, statusDisabledResult)
        Mockito.verify(statusDisabledResult).success(
            mapOf(
                "isSecureScreenEnabled" to false,
                "isAppSwitcherMaskEnabled" to false,
                "isScreenBeingRecorded" to false,
                "isMaskCurrentlyVisible" to false,
                "platform" to "android"
            )
        )
    }
}

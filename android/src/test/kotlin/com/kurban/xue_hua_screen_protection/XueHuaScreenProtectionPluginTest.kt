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
    }
}

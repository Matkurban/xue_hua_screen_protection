package com.kurban.xue_hua_screen_protection

import android.app.Activity
import android.app.Application
import android.content.Context
import android.database.ContentObserver
import android.graphics.Color
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.TypedValue
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.function.Consumer

/**
 * Android implementation of `xue_hua_screen_protection`.
 *
 * Capabilities:
 * - Hardware screenshot & recording block via `WindowManager.LayoutParams.FLAG_SECURE`.
 * - Screenshot detection via Android 14+ (API 34) `Activity.ScreenCaptureCallback` with
 *   `ContentObserver` fallback for earlier Android versions.
 * - Screen recording detection via Android 15+ (API 35) `WindowManager.addScreenRecordingCallback`
 *   combined with `DisplayManager.DisplayListener` virtual/presentation display inspection.
 * - App-switcher / background privacy mask with Android 12+ (API 31) `RenderEffect` blur and
 *   customizable overlay view.
 */
class XueHuaScreenProtectionPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    Application.ActivityLifecycleCallbacks,
    DisplayManager.DisplayListener {

    companion object {
        private const val METHOD_CHANNEL_NAME = "com.kurban.xue_hua_screen_protection/methods"
        private const val EVENT_CHANNEL_NAME = "com.kurban.xue_hua_screen_protection/events"
        private const val MASK_VIEW_TAG = "xue_hua_screen_protection_mask_overlay"
        private const val SCREENSHOT_DEBOUNCE_MS = 1200L
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Protection state
    private var isSecureScreenEnabled: Boolean = false
    private var isScreenBeingRecorded: Boolean = false
    private var isMaskCurrentlyVisible: Boolean = false

    // Mask configuration
    private var maskEnabled: Boolean = false
    private var maskStyle: String = "blur"
    private var maskBlurSigma: Float = 20.0f
    private var maskBackgroundColor: Int = Color.argb(235, 15, 23, 42)
    private var maskTextColor: Int = Color.WHITE
    private var maskTitle: String = "Privacy Protected"
    private var maskSubtitle: String = "Screen content is hidden to protect sensitive information."
    private var maskShowLockIcon: Boolean = true
    private var protectOnWindowBlur: Boolean = true

    // Observers and callbacks
    private var displayManager: DisplayManager? = null
    private var screenshotObserver: ContentObserver? = null
    private var lastScreenshotTimestamp: Long = 0L
    private var windowFocusListener: ViewTreeObserver.OnWindowFocusChangeListener? = null
    private var screenCaptureCallbackObj: Any? = null
    private var screenRecordingCallbackObj: Any? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)

        displayManager =
            applicationContext?.getSystemService(Context.DISPLAY_SERVICE) as? DisplayManager
        displayManager?.registerDisplayListener(this, mainHandler)
        registerMediaStoreScreenshotObserver()
        checkVirtualDisplaysForRecording(emitIfChanged = false)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        displayManager?.unregisterDisplayListener(this)
        unregisterMediaStoreScreenshotObserver()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        applicationContext = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // -------------------------------------------------------------------------
    // MethodChannel Dispatch
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "setSecureScreen" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val applied = applySecureScreenFlag(enabled)
                result.success(applied)
            }

            "isSecureScreenEnabled" -> {
                result.success(isSecureScreenEnabled)
            }

            "configureAppSwitcherProtection" -> {
                maskEnabled = call.argument<Boolean>("enabled") ?: true
                maskStyle = call.argument<String>("style") ?: "blur"
                maskBlurSigma = (call.argument<Number>("blurSigma")?.toFloat() ?: 20.0f)
                    .coerceIn(0.0f, 50.0f)
                maskBackgroundColor = (call.argument<Number>("backgroundColor")?.toInt())
                    ?: Color.argb(235, 15, 23, 42)
                maskTextColor = (call.argument<Number>("textColor")?.toInt()) ?: Color.WHITE
                maskTitle = call.argument<String>("title") ?: "Privacy Protected"
                maskSubtitle = call.argument<String>("subtitle") ?: ""
                maskShowLockIcon = call.argument<Boolean>("showLockIcon") ?: true
                protectOnWindowBlur = call.argument<Boolean>("protectOnWindowBlur") ?: true

                if (!maskEnabled || maskStyle == "none") {
                    setPrivacyMaskVisible(false, reason = "config_disabled")
                } else if (isMaskCurrentlyVisible) {
                    refreshPrivacyMaskView()
                }
                result.success(true)
            }

            "configureWebProtection" -> {
                // Web-only configuration; safely returns false on Android.
                result.success(false)
            }

            "isScreenBeingRecorded" -> {
                checkVirtualDisplaysForRecording(emitIfChanged = false)
                result.success(isScreenBeingRecorded)
            }

            "getProtectionStatus" -> {
                checkVirtualDisplaysForRecording(emitIfChanged = false)
                result.success(
                    mapOf(
                        "isSecureScreenEnabled" to isSecureScreenEnabled,
                        "isAppSwitcherMaskEnabled" to (maskEnabled && maskStyle != "none"),
                        "isScreenBeingRecorded" to isScreenBeingRecorded,
                        "isMaskCurrentlyVisible" to isMaskCurrentlyVisible,
                        "platform" to "android"
                    )
                )
            }

            "getCapabilities" -> {
                val sdkInt = Build.VERSION.SDK_INT
                val limitations = mutableListOf<String>()
                if (sdkInt < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    limitations.add(
                        "Android < 14 uses MediaStore ContentObserver for screenshot detection instead of Activity.ScreenCaptureCallback."
                    )
                }
                if (sdkInt < Build.VERSION_CODES.S) {
                    limitations.add(
                        "Android < 12 does not support RenderEffect window blur; privacy mask uses styled translucent/solid overlay."
                    )
                }
                result.success(
                    mapOf(
                        "platform" to "android",
                        "osVersion" to "Android ${Build.VERSION.RELEASE} (API $sdkInt)",
                        "supportsHardwareAntiScreenshot" to true,
                        "supportsHardwareAntiRecording" to true,
                        "supportsScreenshotDetection" to true,
                        "supportsRecordingDetection" to true,
                        "supportsNativeAppSwitcherMask" to true,
                        "supportsNativeBlurEffect" to (sdkInt >= Build.VERSION_CODES.S),
                        "limitations" to limitations
                    )
                )
            }

            "showPrivacyMask" -> {
                setPrivacyMaskVisible(true, reason = "manual")
                result.success(true)
            }

            "hidePrivacyMask" -> {
                setPrivacyMaskVisible(false, reason = "manual")
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // ActivityAware & Window Management
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attachActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attachActivity(binding.activity)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun attachActivity(newActivity: Activity) {
        activity = newActivity
        newActivity.application.registerActivityLifecycleCallbacks(this)
        if (isSecureScreenEnabled) {
            applySecureScreenFlag(true)
        }
        registerWindowFocusListener(newActivity)
        registerAndroid14ScreenCaptureCallback(newActivity)
        registerAndroid15ScreenRecordingCallback(newActivity)
    }

    private fun detachActivity() {
        val current = activity ?: return
        unregisterAndroid14ScreenCaptureCallback(current)
        unregisterAndroid15ScreenRecordingCallback(current)
        unregisterWindowFocusListener(current)
        setPrivacyMaskVisible(false, reason = "detach")
        current.application.unregisterActivityLifecycleCallbacks(this)
        activity = null
    }

    private fun applySecureScreenFlag(enabled: Boolean): Boolean {
        isSecureScreenEnabled = enabled
        val currentActivity = activity ?: return true
        currentActivity.runOnUiThread {
            if (enabled) {
                currentActivity.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            } else {
                currentActivity.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
        }
        return true
    }

    // -------------------------------------------------------------------------
    // Screenshot & Recording Detection (API 34 / 35 + Fallbacks)
    // -------------------------------------------------------------------------

    private fun registerAndroid14ScreenCaptureCallback(targetActivity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                val callback = Activity.ScreenCaptureCallback {
                    notifyScreenshotDetected(source = "ScreenCaptureCallback_API34")
                }
                targetActivity.registerScreenCaptureCallback(targetActivity.mainExecutor, callback)
                screenCaptureCallbackObj = callback
            } catch (_: Throwable) {
                // Host app might not have granted DETECT_SCREEN_CAPTURE or OEM restricted it.
            }
        }
    }

    private fun unregisterAndroid14ScreenCaptureCallback(targetActivity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback = screenCaptureCallbackObj as? Activity.ScreenCaptureCallback ?: return
            try {
                targetActivity.unregisterScreenCaptureCallback(callback)
            } catch (_: Throwable) {
            } finally {
                screenCaptureCallbackObj = null
            }
        }
    }

    private fun registerAndroid15ScreenRecordingCallback(targetActivity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            try {
                val consumer = Consumer<Int> { state ->
                    val recording =
                        state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
                    updateRecordingState(recording, source = "WindowManager_API35")
                }
                val initialState = targetActivity.windowManager.addScreenRecordingCallback(
                    targetActivity.mainExecutor,
                    consumer
                )
                screenRecordingCallbackObj = consumer
                updateRecordingState(
                    initialState == WindowManager.SCREEN_RECORDING_STATE_VISIBLE,
                    source = "WindowManager_API35_Initial"
                )
            } catch (_: Throwable) {
                // Fallback to DisplayManager listener.
            }
        }
    }

    private fun unregisterAndroid15ScreenRecordingCallback(targetActivity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            @Suppress("UNCHECKED_CAST")
            val consumer = screenRecordingCallbackObj as? Consumer<Int> ?: return
            try {
                targetActivity.windowManager.removeScreenRecordingCallback(consumer)
            } catch (_: Throwable) {
            } finally {
                screenRecordingCallbackObj = null
            }
        }
    }

    private fun registerMediaStoreScreenshotObserver() {
        val resolver = applicationContext?.contentResolver ?: return
        if (screenshotObserver != null) return

        screenshotObserver = object : ContentObserver(mainHandler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                super.onChange(selfChange, uri)
                val uriText = uri?.toString()?.lowercase() ?: return
                if (uriText.contains("images") || uriText.contains("media")) {
                    notifyScreenshotDetected(source = "MediaStoreContentObserver")
                }
            }
        }

        try {
            resolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                screenshotObserver!!
            )
        } catch (_: Throwable) {
        }
    }

    private fun unregisterMediaStoreScreenshotObserver() {
        val resolver = applicationContext?.contentResolver ?: return
        val observer = screenshotObserver ?: return
        try {
            resolver.unregisterContentObserver(observer)
        } catch (_: Throwable) {
        } finally {
            screenshotObserver = null
        }
    }

    private fun notifyScreenshotDetected(source: String) {
        val now = System.currentTimeMillis()
        if (now - lastScreenshotTimestamp < SCREENSHOT_DEBOUNCE_MS) {
            return
        }
        lastScreenshotTimestamp = now
        emitEvent(
            type = "screenshotTaken",
            metadata = mapOf("source" to source)
        )
    }

    override fun onDisplayAdded(displayId: Int) {
        checkVirtualDisplaysForRecording(emitIfChanged = true)
    }

    override fun onDisplayRemoved(displayId: Int) {
        checkVirtualDisplaysForRecording(emitIfChanged = true)
    }

    override fun onDisplayChanged(displayId: Int) {
        checkVirtualDisplaysForRecording(emitIfChanged = true)
    }

    private fun checkVirtualDisplaysForRecording(emitIfChanged: Boolean) {
        val manager = displayManager ?: return
        val displays = manager.displays
        var suspiciousDisplayFound = false
        for (display in displays) {
            if (display.displayId == Display.DEFAULT_DISPLAY) continue
            val name = (display.name ?: "").lowercase()
            // Name-based heuristics only. Treating every non-presentation secondary
            // display as "recording" false-positives on emulators / multi-display OEMs.
            val isVirtualOrMirror =
                name.contains("record") ||
                        name.contains("screencast") ||
                        name.contains("scrcpy") ||
                        name.contains("virtual") ||
                        name.contains("capture") ||
                        name.contains("mirror")
            if (isVirtualOrMirror) {
                suspiciousDisplayFound = true
                break
            }
        }
        if (emitIfChanged) {
            updateRecordingState(suspiciousDisplayFound, source = "DisplayManager")
        } else if (suspiciousDisplayFound) {
            isScreenBeingRecorded = true
        }
    }

    private fun updateRecordingState(recording: Boolean, source: String) {
        if (isScreenBeingRecorded == recording) return
        isScreenBeingRecorded = recording
        emitEvent(
            type = if (recording) "recordingStarted" else "recordingStopped",
            metadata = mapOf("source" to source)
        )
    }

    // -------------------------------------------------------------------------
    // App Switcher / Background Privacy Mask
    // -------------------------------------------------------------------------

    private fun registerWindowFocusListener(targetActivity: Activity) {
        val decorView = targetActivity.window?.decorView ?: return
        unregisterWindowFocusListener(targetActivity)
        val listener = ViewTreeObserver.OnWindowFocusChangeListener { hasFocus ->
            if (!maskEnabled || maskStyle == "none") return@OnWindowFocusChangeListener
            if (!hasFocus && protectOnWindowBlur) {
                setPrivacyMaskVisible(true, reason = "window_focus_lost")
            } else if (hasFocus) {
                setPrivacyMaskVisible(false, reason = "window_focus_gained")
            }
        }
        decorView.viewTreeObserver.addOnWindowFocusChangeListener(listener)
        windowFocusListener = listener
    }

    private fun unregisterWindowFocusListener(targetActivity: Activity) {
        val listener = windowFocusListener ?: return
        val decorView = targetActivity.window?.decorView
        try {
            decorView?.viewTreeObserver?.removeOnWindowFocusChangeListener(listener)
        } catch (_: Throwable) {
        } finally {
            windowFocusListener = null
        }
    }

    override fun onActivityPaused(pausedActivity: Activity) {
        if (pausedActivity === activity && maskEnabled && maskStyle != "none") {
            setPrivacyMaskVisible(true, reason = "activity_paused")
        }
    }

    override fun onActivityResumed(resumedActivity: Activity) {
        if (resumedActivity === activity) {
            setPrivacyMaskVisible(false, reason = "activity_resumed")
        }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}

    private fun setPrivacyMaskVisible(visible: Boolean, reason: String) {
        val currentActivity = activity ?: return
        currentActivity.runOnUiThread {
            val decorView = currentActivity.window?.decorView as? ViewGroup ?: return@runOnUiThread
            val contentView = decorView.findViewById<View>(android.R.id.content)

            if (visible) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    maskStyle == "blur" &&
                    maskBlurSigma > 0f
                ) {
                    contentView?.setRenderEffect(
                        RenderEffect.createBlurEffect(
                            maskBlurSigma,
                            maskBlurSigma,
                            Shader.TileMode.CLAMP
                        )
                    )
                }

                var overlay = decorView.findViewWithTag<View>(MASK_VIEW_TAG)
                if (overlay == null) {
                    overlay = buildPrivacyOverlayView(currentActivity)
                    decorView.addView(
                        overlay,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                    )
                } else {
                    overlay.visibility = View.VISIBLE
                }
                overlay.bringToFront()
                if (!isMaskCurrentlyVisible) {
                    isMaskCurrentlyVisible = true
                    emitEvent("maskShown", mapOf("reason" to reason))
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    contentView?.setRenderEffect(null)
                }
                val overlay = decorView.findViewWithTag<View>(MASK_VIEW_TAG)
                // Hide without destroying so rapid show/hide (Driver / automation)
                // does not thrash view hierarchy — matches Linux/macOS/iOS.
                if (overlay != null) {
                    overlay.visibility = View.GONE
                }
                if (isMaskCurrentlyVisible) {
                    isMaskCurrentlyVisible = false
                    emitEvent("maskHidden", mapOf("reason" to reason))
                }
            }
        }
    }

    private fun refreshPrivacyMaskView() {
        val currentActivity = activity ?: return
        currentActivity.runOnUiThread {
            val decorView = currentActivity.window?.decorView as? ViewGroup ?: return@runOnUiThread
            val existing = decorView.findViewWithTag<View>(MASK_VIEW_TAG)
            if (existing != null) {
                decorView.removeView(existing)
            }
            if (isMaskCurrentlyVisible) {
                isMaskCurrentlyVisible = false
                setPrivacyMaskVisible(true, reason = "config_updated")
            }
        }
    }

    private fun buildPrivacyOverlayView(context: Context): View {
        val container = FrameLayout(context).apply {
            tag = MASK_VIEW_TAG
            isClickable = true
            isFocusable = true
            val alphaAdjustedBg =
                if (maskStyle == "blur" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Color.argb(
                        195,
                        Color.red(maskBackgroundColor),
                        Color.green(maskBackgroundColor),
                        Color.blue(maskBackgroundColor)
                    )
                } else {
                    maskBackgroundColor
                }
            setBackgroundColor(alphaAdjustedBg)
        }

        val column = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            val pad = dpToPx(context, 32f)
            setPadding(pad, pad, pad, pad)
        }

        if (maskShowLockIcon) {
            val badgeSize = dpToPx(context, 64f)
            val badge = TextView(context).apply {
                text = "🔒"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.argb(38, 255, 255, 255))
                }
                layoutParams = LinearLayout.LayoutParams(badgeSize, badgeSize).apply {
                    bottomMargin = dpToPx(context, 16f)
                }
            }
            column.addView(badge)
        }

        if (maskTitle.isNotEmpty()) {
            val titleView = TextView(context).apply {
                text = maskTitle
                setTextColor(maskTextColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                gravity = Gravity.CENTER
                layoutParams = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = dpToPx(context, 8f)
                }
            }
            column.addView(titleView)
        }

        if (maskSubtitle.isNotEmpty()) {
            val subtitleView = TextView(context).apply {
                text = maskSubtitle
                setTextColor(
                    Color.argb(
                        210,
                        Color.red(maskTextColor),
                        Color.green(maskTextColor),
                        Color.blue(maskTextColor)
                    )
                )
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                gravity = Gravity.CENTER
            }
            column.addView(subtitleView)
        }

        container.addView(
            column,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        return container
    }

    private fun dpToPx(context: Context, dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        ).toInt()
    }

    // -------------------------------------------------------------------------
    // Event Dispatch
    // -------------------------------------------------------------------------

    private fun emitEvent(type: String, metadata: Map<String, Any?> = emptyMap()) {
        val payload = mapOf(
            "type" to type,
            "timestamp" to System.currentTimeMillis(),
            "platform" to "android",
            "isCaptured" to isScreenBeingRecorded,
            "metadata" to metadata
        )
        mainHandler.post {
            eventSink?.success(payload)
            try {
                methodChannel.invokeMethod("onProtectionEvent", payload)
            } catch (_: Throwable) {
            }
        }
    }
}

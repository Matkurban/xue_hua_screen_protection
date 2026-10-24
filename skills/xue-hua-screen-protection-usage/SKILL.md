---
name: xue-hua-screen-protection-usage
description: >-
  Use when the user is working with xue_hua_screen_protection APIs to implement
  cross-platform anti-screenshot, anti-screen-recording, capture detection,
  app-switcher blur masks, Web browser content hardening, or security watermarks
  across Android, iOS, macOS, Windows, Linux, and Web.
---

# xue-hua-screen-protection-usage

Provide idiomatic integration patterns, platform difference handling, and best practices for the `xue_hua_screen_protection` Flutter plugin across Android, iOS, macOS, Windows, Linux, and Web.

## When to Use

- Enabling or disabling OS-level screenshot and screen recording protection (`enableSecureScreen`, `disableSecureScreen`, `setSecureScreen`)
- Configuring app-switcher, background, or inactive-window privacy overlays (`configureAppSwitcherProtection`, `ScreenProtectionMaskConfig`)
- Listening to real-time screenshot or screen recording events (`onScreenCaptured`, `onScreenRecordingChanged`, `onProtectionEvent`)
- Hardening Flutter Web apps against printing, context menus, and capture shortcuts (`configureWebProtection`, `WebProtectionConfig`)
- Wrapping sensitive routes or widgets with declarative protection (`ScreenProtectionScope`) or diagonal watermarks (`ScreenProtectionWatermark`)
- Inspecting platform capabilities and limitations at runtime (`getCapabilities`, `getProtectionStatus`)

## Guidelines

- Always call `WidgetsFlutterBinding.ensureInitialized()` before invoking `XueHuaScreenProtection.instance` methods prior to `runApp()`.
- Prefer `ScreenProtectionScope` for route-scoped protection (such as payment, credential, or confidential document screens) so protection automatically disables when the user leaves the route.
- Use `XueHuaScreenProtection.instance.enableSecureScreen()` and `configureAppSwitcherProtection(...)` at startup when the entire application requires persistent protection.
- Always cancel `StreamSubscription` instances for `onScreenCaptured`, `onScreenRecordingChanged`, or `onProtectionEvent` inside `State.dispose()`.
- Check `getCapabilities()` when building adaptive security UIs on Linux or Web, and combine `ScreenProtectionWatermark` with `protectOnWindowBlur: true` on platforms where `supportsHardwareAntiScreenshot` is `false`.

## Steps

1. Access `XueHuaScreenProtection.instance` to configure global protection or wrap a route with `ScreenProtectionScope`.
2. Call `enableSecureScreen()` to activate OS-level anti-screenshot and anti-recording flags.
3. Call `configureAppSwitcherProtection(ScreenProtectionMaskConfig(...))` to configure frosted blur (`ScreenProtectionMaskStyle.blur`) or solid color (`ScreenProtectionMaskStyle.solidColor`) overlays when switching apps or losing window focus.
4. On Web targets, call `configureWebProtection(WebProtectionConfig(...))` to inject `@media print` suppression and intercept capture shortcuts.
5. Subscribe to `onScreenCaptured` and `onScreenRecordingChanged` to react to screenshot attempts or active screen recording.
6. Wrap sensitive content with `ScreenProtectionWatermark` to deter physical camera leaks.

## Examples

### Global Setup and Event Listening

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

class SecureAppBootstrapper {
  final XueHuaScreenProtection _protection = XueHuaScreenProtection.instance;
  StreamSubscription<ScreenProtectionEvent>? _captureSub;
  StreamSubscription<bool>? _recordingSub;

  Future<void> initialize() async {
    await _protection.enableSecureScreen();

    await _protection.configureAppSwitcherProtection(
      const ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.blur,
        blurSigma: 20.0,
        title: 'Privacy Protected',
        subtitle: 'Sensitive content is hidden while inactive.',
        showLockIcon: true,
        protectOnWindowBlur: true,
      ),
    );

    await _protection.configureWebProtection(
      const WebProtectionConfig(
        disableContextMenu: true,
        disablePrint: true,
        disableDragAndSelect: true,
        interceptCaptureShortcuts: true,
        blurOnVisibilityChange: true,
      ),
    );

    _captureSub = _protection.onScreenCaptured.listen((event) {
      debugPrint('Screenshot detected on ${event.platform}: ${event.metadata}');
    });

    _recordingSub = _protection.onScreenRecordingChanged.listen((isRecording) {
      debugPrint('Screen recording state changed: $isRecording');
    });
  }

  Future<void> dispose() async {
    await _captureSub?.cancel();
    await _recordingSub?.cancel();
  }
}
```

### Declarative Route Protection and Watermark

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

class ConfidentialReportPage extends StatelessWidget {
  const ConfidentialReportPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) {
    return ScreenProtectionScope(
      enableSecureScreen: true,
      hideContentWhileRecording: true,
      watermarkText: 'CONFIDENTIAL - $userId',
      watermarkSubText: 'DO NOT CAPTURE OR DISTRIBUTE',
      onScreenshotTaken: (event) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screenshots are restricted.')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Confidential Report')),
        body: const Center(child: Text('Protected financial records')),
      ),
    );
  }
}
```

## Gotchas

- **Android (`FLAG_SECURE` & API Levels)**: `FLAG_SECURE` blocks screenshots and recordings on Android 7.0+ (API 24+). Official `Activity.ScreenCaptureCallback` requires Android 14+ (API 34), `WindowManager.addScreenRecordingCallback` requires Android 15+ (API 35), and `RenderEffect` window blur requires Android 12+ (API 31). Earlier Android versions automatically use `MediaStore` `ContentObserver`, `DisplayManager`, and translucent/solid overlays.
- **iOS (`UITextField` Secure Layer)**: `enableSecureScreen()` mounts the root view inside a secure `UITextField` canvas layer so screenshots and screen recordings render blank while touch events remain interactive. Test on physical devices or via Simulator `Device -> Trigger Screenshot`.
- **macOS (`NSWindow.sharingType`)**: Sets `window.sharingType = .none`, excluding the window from macOS system screenshots, QuickTime recordings, and screen-sharing apps.
- **Windows (`SetWindowDisplayAffinity`)**: Uses `WDA_EXCLUDEFROMCAPTURE` on Windows 10 Version 2004+ (Build 19041+) and falls back to `WDA_MONITOR` on older builds.
- **Linux and Web**: OS-level screenshot blocking is not exposed by X11/Wayland compositors or browser sandboxes (`supportsHardwareAntiScreenshot` is `false`). Always pair `protectOnWindowBlur: true` with `ScreenProtectionWatermark` on Linux and Web.

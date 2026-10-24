# xue_hua_screen_protection

**English** | [简体中文](./README_ZH.md)

A comprehensive, production-grade cross-platform Flutter plugin for **screen privacy protection, anti-screenshot, anti-screen-recording, capture detection, app-switcher blur masks, and anti-photo-leak watermarks** across **Android, iOS, macOS, Windows, Linux, and Web**.

- **Author**: Matkurban (`3496354336@qq.com`)
- **Repository**: [https://github.com/Matkurban/xue_hua_screen_protection](https://github.com/Matkurban/xue_hua_screen_protection)
- **Version**: `1.0.0`

## Features

- **Hardware Anti-Screenshot & Anti-Recording**: Prevents system screenshots, screen recording, and window sharing using native OS APIs on Android, iOS, macOS, and Windows.
- **Real-Time Capture & Recording Detection**: Emits typed events (`onScreenCaptured`, `onScreenRecordingChanged`, `onProtectionEvent`) when a user captures a screenshot or starts/stops screen recording or mirroring.
- **App Switcher & Inactive Window Privacy Mask**: Automatically covers the application window with a native frosted-glass blur (`RenderEffect`, `UIVisualEffectView`, `NSVisualEffectView`, CSS `backdrop-filter`) or solid shield when entering the background, app switcher, or losing focus.
- **Web Browser Content Hardening**: Injects `@media print` rules to block printing/PDF export, disables right-click context menus and text/image dragging, and intercepts `PrintScreen`, `Ctrl/Cmd+P`, `Ctrl/Cmd+S`, and DevTools shortcuts.
- **Declarative Flutter Widgets**:
  - `ScreenProtectionScope`: Automatically enables screen protection while mounted, shields content during active recording, and restores state on dispose.
  - `ScreenProtectionWatermark`: Renders a high-performance, non-interactive (`IgnorePointer`) diagonal tiled watermark to deter physical camera leaks.
- **Runtime Capability Inspection**: Query `getCapabilities()` to inspect exact OS support and platform limitations at runtime.
- **Bundled AI Agent Skill**: Ships with a standard [Dart Package Skill](https://dart.dev/tools/pub/package-skills) in `skills/xue-hua-screen-protection-usage/SKILL.md`.

## Platform Support & Implementation Matrix

| Feature                      | Android (API 24+)                                      | iOS (15.0+)                              | macOS (12.0+)                                | Windows (10/11+)                                      | Linux (GTK 3)                | Web (Modern Browsers)                  |
|:-----------------------------|:-------------------------------------------------------|:-----------------------------------------|:---------------------------------------------|:------------------------------------------------------|:-----------------------------|:---------------------------------------|
| **Anti-Screenshot**          | `FLAG_SECURE`                                          | Secure `UITextField` layer               | `NSWindow.sharingType = .none`               | `SetWindowDisplayAffinity` (`WDA_EXCLUDEFROMCAPTURE`) | Focus-out mask + Watermark   | `@media print` + Key intercept         |
| **Anti-Recording**           | `FLAG_SECURE`                                          | Secure `UITextField` layer               | `NSWindow.sharingType = .none`               | `SetWindowDisplayAffinity` (`WDA_EXCLUDEFROMCAPTURE`) | Focus-out mask + Watermark   | Visibility mask + Watermark            |
| **Screenshot Detection**     | API 34 `ScreenCaptureCallback` + `ContentObserver`     | `userDidTakeScreenshotNotification`      | `NSMetadataQuery` (`kMDItemIsScreenCapture`) | `WM_CLIPBOARDUPDATE` + `VK_SNAPSHOT`                  | Not supported by X11/Wayland | `PrintScreen` / `Cmd+Shift+3/4/5`      |
| **Recording Detection**      | API 35 `addScreenRecordingCallback` + `DisplayManager` | `UIScreen.capturedDidChangeNotification` | `NSWorkspace` capture check                  | Blocked at DWM hardware level                         | Not supported by X11/Wayland | Not exposed by browser sandbox         |
| **App Switcher / Blur Mask** | `ActivityLifecycle` + API 31 `RenderEffect` blur       | `UIVisualEffectView` blur / solid shield | `NSVisualEffectView` blur / solid shield     | `WM_ACTIVATE` Win32 top-most shield                   | GTK `focus-out-event` mask   | `visibilitychange` + `backdrop-filter` |
| **Security Watermark**       | Supported                                              | Supported                                | Supported                                    | Supported                                             | Supported                    | Supported                              |

## Installation

Add `xue_hua_screen_protection` to your `pubspec.yaml`:

```yaml
dependencies:
  xue_hua_screen_protection: ^1.0.0
```

Or reference the Git repository directly:

```yaml
dependencies:
  xue_hua_screen_protection:
    git:
      url: https://github.com/Matkurban/xue_hua_screen_protection.git
```

### Installing the Bundled AI Package Skill

This package ships with an official AI coding agent skill following [Ship skills with packages](https://dart.dev/tools/pub/package-skills). Consumers can install it via:

```bash
dart run skills@ get
```

## Platform Configuration

### Android

The plugin automatically merges the Android 14+ (API 34) screenshot detection and Android 15+ (API 35) screen recording detection permissions in its `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.DETECT_SCREEN_CAPTURE" />
<uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING" />
```

No manual runtime permission prompt is required for `DETECT_SCREEN_CAPTURE` or `DETECT_SCREEN_RECORDING` (they are install-time non-dangerous permissions).

### iOS & macOS

No additional `Info.plist` permissions are required. Minimum deployment targets:
- **iOS**: `15.0`
- **macOS**: `12.0`

### Windows, Linux & Web

No additional native configuration is required.

## Usage

### 1. Imperative Control (`XueHuaScreenProtection.instance`)

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

Future<void> setupScreenSecurity() async {
  final protection = XueHuaScreenProtection.instance;

  // 1. Enable OS-level anti-screenshot & anti-recording protection
  await protection.enableSecureScreen();

  // 2. Configure the app-switcher / inactive-window privacy mask
  await protection.configureAppSwitcherProtection(
    const ScreenProtectionMaskConfig(
      enabled: true,
      style: ScreenProtectionMaskStyle.blur,
      blurSigma: 20.0,
      backgroundColor: Color(0xEB0F172A),
      textColor: Colors.white,
      title: 'Privacy Protected',
      subtitle: 'Screen content is hidden to protect sensitive information.',
      showLockIcon: true,
      protectOnWindowBlur: true,
    ),
  );

  // 3. Configure Web browser hardening (safe no-op on native platforms)
  await protection.configureWebProtection(
    const WebProtectionConfig(
      disableContextMenu: true,
      disablePrint: true,
      disableDragAndSelect: true,
      interceptCaptureShortcuts: true,
      blurOnVisibilityChange: true,
    ),
  );

  // 4. Listen for screenshot events
  protection.onScreenCaptured.listen((ScreenProtectionEvent event) {
    debugPrint('Screenshot detected on ${event.platform}: ${event.metadata}');
  });

  // 5. Listen for screen recording / mirroring changes
  protection.onScreenRecordingChanged.listen((bool isRecording) {
    debugPrint('Screen recording active: $isRecording');
  });
}
```

### 2. Declarative Route Protection (`ScreenProtectionScope`)

Wrap any sensitive route or subtree with `ScreenProtectionScope` to automatically enable protection when entering the page and restore settings when leaving:

```dart
import 'package:flutter/material.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

class PaymentVaultPage extends StatelessWidget {
  const PaymentVaultPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenProtectionScope(
      enableSecureScreen: true,
      hideContentWhileRecording: true,
      watermarkText: 'CONFIDENTIAL • UID-8842',
      watermarkSubText: '2026-10-24 • DO NOT DISTRIBUTE',
      onScreenshotTaken: (event) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Screenshots are restricted on this page.')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment Vault')),
        body: const Center(child: Text('Sensitive Account Details')),
      ),
    );
  }
}
```

### 3. Standalone Anti-Photo-Leak Watermark (`ScreenProtectionWatermark`)

```dart
ScreenProtectionWatermark(
  enabled: true,
  text: 'INTERNAL ONLY • Matkurban',
  subText: 'Session #9041',
  angleDegrees: -24.0,
  opacity: 0.12,
  child: YourSensitiveWidget(),
)
```

### 4. Inspecting Platform Capabilities & Status

```dart
final capabilities = await XueHuaScreenProtection.instance.getCapabilities();
debugPrint('Hardware anti-screenshot: ${capabilities.supportsHardwareAntiScreenshot}');
for (final note in capabilities.limitations) {
  debugPrint('Platform note: $note');
}

final status = await XueHuaScreenProtection.instance.getProtectionStatus();
debugPrint('Current status: $status');
```

## Important Platform Notes & Caveats

1. **iOS Simulator vs. Physical Device**: On iOS, the secure `UITextField` layer masks content captured via `UIScreen` and system screenshot/recording pipelines. Always verify anti-screenshot behavior using the iOS device screenshot shortcut (`Side Button + Volume Up` or Simulator `Device -> Trigger Screenshot`), not macOS host window capture of the Simulator app.
2. **Android < 14 Screenshot Detection**: Android 14 (API 34) introduced the official `Activity.ScreenCaptureCallback` API. On Android 7.0–13, the plugin falls back to a debounced `MediaStore` `ContentObserver`.When `FLAG_SECURE` is enabled on Android, the OS blocks the screenshot from being saved, so `ContentObserver` will not fire on Android < 14 while `FLAG_SECURE` is active.
3. **Windows `WDA_EXCLUDEFROMCAPTURE`**: On Windows 10 Version 2004 (Build 19041) and Windows 11, `WDA_EXCLUDEFROMCAPTURE` excludes the window from screenshots and OBS/Teams/Zoom captures. On older Windows builds, the plugin automatically falls back to `WDA_MONITOR` (which renders the window black in captures).
4. **Linux & Web Security Model**: Neither Linux desktop compositors (X11/Wayland) nor Web browsers allow unprivileged applications to block OS-level screenshot tools. On Linux and Web, combine `configureAppSwitcherProtection` (focus-out blur mask), `configureWebProtection`, and `ScreenProtectionWatermark` for defense-in-depth.

## License

See [LICENSE](./LICENSE) for details.

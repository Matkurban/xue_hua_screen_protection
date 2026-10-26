## 1.0.3

* macOS: real screen-recording heuristics via `CGWindowListCopyWindowInfo` and capture helper apps (was only `screencaptureui`); clipboard screenshot UTIs via pasteboard polling.
* macOS / iOS: hide privacy overlay without destroying the native view (Driver-friendly, matches Linux).
* Example: set `version` to clear iOS build name/number warnings; extend flutter_driver and integration_test with macOS/iOS capability assertions.
* Verified green on macOS (unit, integration_test, flutter_driver ×9) and iOS simulator smoke (integration_test).

## 1.0.2

* Linux: real privacy overlay for app-switcher / focus-out masking; secure-screen enables mask fallback and cleanly undoes it on disable; focus-out debounce; hide overlay without destroying (fixes Flutter Driver input).
* `ScreenProtectionScope` applies native configuration after the first frame to avoid route-push frame-sync hangs.
* Example: Flutter Driver suite (`example/test_driver`) covering secure screen, privacy mask, scoped vault, web config; UI ValueKeys and navigator helpers for reliable automation.
* Verified green on Linux and Windows: unit, integration_test, and flutter_driver (9 cases).

## 1.0.1

* Shortened `pubspec.yaml` `description` to meet pub.dev length guidance (60–180 characters).
* Compatible with CMake 4.x by bumping example googletest to v1.15.2 (fixes Windows/Linux `Unable to generate build files`).
* Lazily initialize `MethodChannel` / default plugin instance to avoid early binding issues.
* Replace deprecated Material imports in tests.

## 1.0.0

* Initial stable release of `xue_hua_screen_protection` by Matkurban (`3496354336@qq.com`).
* Implemented cross-platform hardware anti-screenshot and anti-screen-recording (`enableSecureScreen`, `disableSecureScreen`, `setSecureScreen`) across Android (`FLAG_SECURE`), iOS (secure `UITextField` canvas layer), macOS (`NSWindow.sharingType = .none`), and Windows (`SetWindowDisplayAffinity` with `WDA_EXCLUDEFROMCAPTURE` / `WDA_MONITOR`).
* Added real-time screenshot and screen recording detection (`onScreenCaptured`, `onScreenRecordingChanged`, `onProtectionEvent`) supporting Android 14+ `ScreenCaptureCallback`, Android 15+ `addScreenRecordingCallback`, iOS `userDidTakeScreenshotNotification` & `UIScreen.capturedDidChangeNotification`, macOS `NSMetadataQuery`, Windows `WM_CLIPBOARDUPDATE` / `VK_SNAPSHOT`, and Web shortcut interception.
* Added configurable app-switcher and inactive-window privacy masks (`configureAppSwitcherProtection`, `ScreenProtectionMaskConfig`) with native frosted blur (`RenderEffect`, `UIVisualEffectView`, `NSVisualEffectView`, CSS `backdrop-filter`) and solid shield styles across all 6 platforms.
* Added Web browser hardening (`configureWebProtection`, `WebProtectionConfig`) including `@media print` suppression, context-menu blocking, drag/select prevention, and capture shortcut interception.
* Added `ScreenProtectionWatermark` widget for tiled diagonal anti-camera-leak watermarks and `ScreenProtectionScope` widget for route-scoped declarative protection.
* Added `getCapabilities()` and `getProtectionStatus()` for runtime platform capability inspection.
* Shipped standard package skill under `skills/xue-hua-screen-protection-usage/SKILL.md`.

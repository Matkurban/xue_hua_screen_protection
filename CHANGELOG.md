## 1.0.0

* Initial stable release of `xue_hua_screen_protection` by Matkurban (`3496354336@qq.com`).
* Implemented cross-platform hardware anti-screenshot and anti-screen-recording (`enableSecureScreen`, `disableSecureScreen`, `setSecureScreen`) across Android (`FLAG_SECURE`), iOS (secure `UITextField` canvas layer), macOS (`NSWindow.sharingType = .none`), and Windows (`SetWindowDisplayAffinity` with `WDA_EXCLUDEFROMCAPTURE` / `WDA_MONITOR`).
* Added real-time screenshot and screen recording detection (`onScreenCaptured`, `onScreenRecordingChanged`, `onProtectionEvent`) supporting Android 14+ `ScreenCaptureCallback`, Android 15+ `addScreenRecordingCallback`, iOS `userDidTakeScreenshotNotification` & `UIScreen.capturedDidChangeNotification`, macOS `NSMetadataQuery`, Windows `WM_CLIPBOARDUPDATE` / `VK_SNAPSHOT`, and Web shortcut interception.
* Added configurable app-switcher and inactive-window privacy masks (`configureAppSwitcherProtection`, `ScreenProtectionMaskConfig`) with native frosted blur (`RenderEffect`, `UIVisualEffectView`, `NSVisualEffectView`, CSS `backdrop-filter`) and solid shield styles across all 6 platforms.
* Added Web browser hardening (`configureWebProtection`, `WebProtectionConfig`) including `@media print` suppression, context-menu blocking, drag/select prevention, and capture shortcut interception.
* Added `ScreenProtectionWatermark` widget for tiled diagonal anti-camera-leak watermarks and `ScreenProtectionScope` widget for route-scoped declarative protection.
* Added `getCapabilities()` and `getProtectionStatus()` for runtime platform capability inspection.
* Shipped standard package skill under `skills/xue-hua-screen-protection-usage/SKILL.md`.

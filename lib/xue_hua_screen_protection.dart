import 'src/models/screen_protection_models.dart';
import 'xue_hua_screen_protection_platform_interface.dart';

export 'src/models/screen_protection_models.dart';
export 'src/widgets/screen_protection_scope.dart';
export 'src/widgets/screen_protection_watermark.dart';
export 'xue_hua_screen_protection_platform_interface.dart';

/// Unified controller for cross-platform screen privacy protection,
/// anti-screenshot/recording, capture detection, and app-switcher blur masks.
///
/// Use [XueHuaScreenProtection.instance] (or construct an instance directly) to
/// configure protection across Android, iOS, macOS, Windows, Linux, and Web:
///
/// ```dart
/// final protection = XueHuaScreenProtection.instance;
/// await protection.enableSecureScreen();
/// await protection.configureAppSwitcherProtection(
///   const ScreenProtectionMaskConfig(
///     enabled: true,
///     style: ScreenProtectionMaskStyle.blur,
///     blurSigma: 20.0,
///   ),
/// );
/// ```
class XueHuaScreenProtection {
  /// Constructs a [XueHuaScreenProtection] instance.
  const XueHuaScreenProtection();

  /// Shared singleton instance of [XueHuaScreenProtection].
  static const XueHuaScreenProtection instance = XueHuaScreenProtection();

  XueHuaScreenProtectionPlatform get _platform =>
      XueHuaScreenProtectionPlatform.instance;

  /// Enables OS-level anti-screenshot and anti-screen-recording protection.
  ///
  /// - **Android**: Sets `WindowManager.LayoutParams.FLAG_SECURE` on the active
  ///   `Activity` window.
  /// - **iOS**: Mounts the root window inside a secure `UITextField` container
  ///   layer so system screenshots and recordings render blank/hidden.
  /// - **macOS**: Sets `NSWindow.sharingType = .none` on the main application
  ///   window.
  /// - **Windows**: Applies `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)`
  ///   (with fallback to `WDA_MONITOR`).
  /// - **Web**: Injects `@media print` suppression, disables context menus/drag,
  ///   and intercepts capture shortcuts.
  /// - **Linux**: Activates focus-out privacy masking (X11/Wayland compositors
  ///   do not expose an application-level `FLAG_SECURE` equivalent).
  Future<bool> enableSecureScreen() => _platform.setSecureScreen(true);

  /// Disables OS-level anti-screenshot and anti-screen-recording protection.
  Future<bool> disableSecureScreen() => _platform.setSecureScreen(false);

  /// Sets whether OS-level secure screen protection is [enabled].
  Future<bool> setSecureScreen(bool enabled) =>
      _platform.setSecureScreen(enabled);

  /// Queries whether OS-level secure screen protection is currently enabled.
  Future<bool> isSecureScreenEnabled() => _platform.isSecureScreenEnabled();

  /// Configures the privacy overlay shown when the application enters the OS
  /// app switcher, background, or loses window focus.
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) => _platform.configureAppSwitcherProtection(config);

  /// Configures Web-specific hardening rules (no-op on native platforms).
  Future<bool> configureWebProtection(WebProtectionConfig config) =>
      _platform.configureWebProtection(config);

  /// Queries whether the screen is currently being recorded, mirrored, or
  /// captured by an external display.
  Future<bool> isScreenBeingRecorded() => _platform.isScreenBeingRecorded();

  /// Retrieves a complete snapshot of the active protection status.
  Future<ScreenProtectionStatus> getProtectionStatus() =>
      _platform.getProtectionStatus();

  /// Retrieves the screen protection capabilities supported by the current
  /// operating system and runtime environment.
  Future<ScreenProtectionCapabilities> getCapabilities() =>
      _platform.getCapabilities();

  /// Manually displays the native/DOM privacy mask overlay on top of the
  /// application window.
  Future<bool> showPrivacyMask() => _platform.showPrivacyMask();

  /// Manually hides the native/DOM privacy mask overlay.
  Future<bool> hidePrivacyMask() => _platform.hidePrivacyMask();

  /// Broadcast stream of all [ScreenProtectionEvent]s emitted by the platform.
  Stream<ScreenProtectionEvent> get onProtectionEvent =>
      _platform.onProtectionEvent;

  /// Filtered stream emitting events whenever a screenshot or blocked capture
  /// shortcut is detected.
  Stream<ScreenProtectionEvent> get onScreenCaptured =>
      _platform.onProtectionEvent.where(
        (ScreenProtectionEvent event) =>
            event.type == ScreenProtectionEventType.screenshotTaken ||
            event.type == ScreenProtectionEventType.shortcutBlocked,
      );

  /// Filtered stream emitting `true` when screen recording starts and `false`
  /// when screen recording stops.
  Stream<bool> get onScreenRecordingChanged => _platform.onProtectionEvent
      .where(
        (ScreenProtectionEvent event) =>
            event.type == ScreenProtectionEventType.recordingStarted ||
            event.type == ScreenProtectionEventType.recordingStopped,
      )
      .map(
        (ScreenProtectionEvent event) =>
            event.type == ScreenProtectionEventType.recordingStarted,
      );
}

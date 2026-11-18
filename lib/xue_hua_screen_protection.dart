import 'package:flutter/foundation.dart';

import 'src/models/screen_protection_models.dart';
import 'src/screen_protection_backend.dart';
import 'src/widgets/screen_protection_coordinator.dart';

export 'src/models/screen_protection_models.dart';
export 'src/screen_protection_backend.dart' show ScreenProtectionBackend;
export 'src/widgets/screen_protection_scope.dart';
export 'src/widgets/screen_protection_watermark.dart';

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

  /// Replaces the active [ScreenProtectionBackend] for unit/widget tests.
  @visibleForTesting
  static void setBackendForTesting(ScreenProtectionBackend backend) {
    ScreenProtectionBackendRegistry.register(backend);
  }

  /// Restores the default Pigeon-powered native [ScreenProtectionBackend].
  @visibleForTesting
  static void resetBackendForTesting() {
    ScreenProtectionBackendRegistry.reset();
  }

  ScreenProtectionBackend get _backend =>
      ScreenProtectionBackendRegistry.instance;

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
  Future<bool> enableSecureScreen() =>
      ScreenProtectionCoordinator.instance.setImperativeSecureScreen(true);

  /// Disables OS-level anti-screenshot and anti-screen-recording protection.
  Future<bool> disableSecureScreen() =>
      ScreenProtectionCoordinator.instance.setImperativeSecureScreen(false);

  /// Sets whether OS-level secure screen protection is [enabled].
  Future<bool> setSecureScreen(bool enabled) =>
      ScreenProtectionCoordinator.instance.setImperativeSecureScreen(enabled);

  /// Queries whether OS-level secure screen protection is currently enabled.
  Future<bool> isSecureScreenEnabled() => _backend.isSecureScreenEnabled();

  /// Configures the privacy overlay shown when the application enters the OS
  /// app switcher, background, or loses window focus.
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) => ScreenProtectionCoordinator.instance.setImperativeMaskConfig(config);

  /// Configures Web-specific hardening rules (no-op on native platforms).
  Future<bool> configureWebProtection(WebProtectionConfig config) =>
      _backend.configureWebProtection(config);

  /// Queries whether the screen is currently being recorded, mirrored, or
  /// captured by an external display.
  Future<bool> isScreenBeingRecorded() => _backend.isScreenBeingRecorded();

  /// Retrieves a complete snapshot of the active protection status.
  Future<ScreenProtectionStatus> getProtectionStatus() =>
      _backend.getProtectionStatus();

  /// Retrieves the screen protection capabilities supported by the current
  /// operating system and runtime environment.
  Future<ScreenProtectionCapabilities> getCapabilities() =>
      _backend.getCapabilities();

  /// Manually displays the native/DOM privacy mask overlay on top of the
  /// application window.
  Future<bool> showPrivacyMask() => _backend.showPrivacyMask();

  /// Manually hides the native/DOM privacy mask overlay.
  Future<bool> hidePrivacyMask() => _backend.hidePrivacyMask();

  /// Broadcast stream of all [ScreenProtectionEvent]s emitted by the platform.
  Stream<ScreenProtectionEvent> get onProtectionEvent =>
      _backend.onProtectionEvent;

  /// Filtered stream emitting events whenever a screenshot or blocked capture
  /// shortcut is detected.
  Stream<ScreenProtectionEvent> get onScreenCaptured =>
      _backend.onProtectionEvent.where(
        (ScreenProtectionEvent event) =>
            event.type == ScreenProtectionEventType.screenshotTaken ||
            event.type == ScreenProtectionEventType.shortcutBlocked,
      );

  /// Filtered stream emitting `true` when screen recording starts and `false`
  /// when screen recording stops.
  Stream<bool> get onScreenRecordingChanged => _backend.onProtectionEvent
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

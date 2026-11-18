import 'models/screen_protection_models.dart';
import 'pigeon/pigeon_screen_protection_backend.dart';

/// Contract implemented by [PigeonScreenProtectionBackend] on native platforms
/// (Android, iOS, macOS, Windows, Linux) and [XueHuaScreenProtectionWeb] on Web.
abstract interface class ScreenProtectionBackend {
  /// Enables or disables OS-level screenshot and screen recording protection.
  Future<bool> setSecureScreen(bool enabled);

  /// Queries whether OS-level secure screen protection is currently enabled.
  Future<bool> isSecureScreenEnabled();

  /// Configures the app-switcher / inactive-window privacy overlay.
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  );

  /// Configures Web-specific content protection rules (returns `false` on
  /// native hosts).
  Future<bool> configureWebProtection(WebProtectionConfig config);

  /// Queries whether the screen is currently being recorded, mirrored, or
  /// captured.
  Future<bool> isScreenBeingRecorded();

  /// Retrieves a comprehensive snapshot of the current screen protection state.
  Future<ScreenProtectionStatus> getProtectionStatus();

  /// Retrieves the screen protection capabilities supported by the current
  /// platform and OS version.
  Future<ScreenProtectionCapabilities> getCapabilities();

  /// Manually displays the native/DOM privacy mask overlay on top of the
  /// application window.
  Future<bool> showPrivacyMask();

  /// Manually hides the native/DOM privacy mask overlay.
  Future<bool> hidePrivacyMask();

  /// Broadcast stream of real-time [ScreenProtectionEvent] notifications.
  Stream<ScreenProtectionEvent> get onProtectionEvent;
}

/// Internal registry holding the active [ScreenProtectionBackend].
///
/// Defaults lazily to [PigeonScreenProtectionBackend]. Web plugin registration
/// and unit tests can replace it via [register] and [reset].
final class ScreenProtectionBackendRegistry {
  ScreenProtectionBackendRegistry._();

  static ScreenProtectionBackend? _instance;
  static int _epoch = 0;

  /// Active [ScreenProtectionBackend] instance.
  static ScreenProtectionBackend get instance =>
      _instance ??= PigeonScreenProtectionBackend();

  /// Monotonically incremented whenever [register] or [reset] is called.
  static int get epoch => _epoch;

  /// Installs [backend] as the active backend implementation.
  static void register(ScreenProtectionBackend backend) {
    _instance = backend;
    _epoch++;
  }

  /// Clears any registered backend override so the default Pigeon backend is
  /// lazily recreated on next access.
  static void reset() {
    _instance = null;
    _epoch++;
  }
}

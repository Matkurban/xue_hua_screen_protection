import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'src/models/screen_protection_models.dart';
import 'xue_hua_screen_protection_method_channel.dart';

/// The interface that implementations of `xue_hua_screen_protection` must
/// implement.
///
/// Platform implementations should extend this class rather than implement it
/// directly, as newly added methods are not considered breaking changes.
abstract class XueHuaScreenProtectionPlatform extends PlatformInterface {
  /// Constructs a [XueHuaScreenProtectionPlatform].
  XueHuaScreenProtectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static XueHuaScreenProtectionPlatform _instance =
      MethodChannelXueHuaScreenProtection();

  /// The default instance of [XueHuaScreenProtectionPlatform] to use.
  ///
  /// Defaults to [MethodChannelXueHuaScreenProtection].
  static XueHuaScreenProtectionPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [XueHuaScreenProtectionPlatform] when
  /// they register themselves.
  static set instance(XueHuaScreenProtectionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Enables or disables OS-level screenshot and screen recording protection.
  Future<bool> setSecureScreen(bool enabled) {
    throw UnimplementedError('setSecureScreen() has not been implemented.');
  }

  /// Queries whether OS-level secure screen protection is currently enabled.
  Future<bool> isSecureScreenEnabled() {
    throw UnimplementedError(
      'isSecureScreenEnabled() has not been implemented.',
    );
  }

  /// Configures the app-switcher / inactive-window privacy overlay.
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) {
    throw UnimplementedError(
      'configureAppSwitcherProtection() has not been implemented.',
    );
  }

  /// Configures Web-specific content protection rules (no-op on native
  /// platforms, returns `false` when not running on Web).
  Future<bool> configureWebProtection(WebProtectionConfig config) {
    throw UnimplementedError(
      'configureWebProtection() has not been implemented.',
    );
  }

  /// Queries whether the screen is currently being recorded, mirrored, or
  /// captured.
  Future<bool> isScreenBeingRecorded() {
    throw UnimplementedError(
      'isScreenBeingRecorded() has not been implemented.',
    );
  }

  /// Retrieves a comprehensive snapshot of the current screen protection state.
  Future<ScreenProtectionStatus> getProtectionStatus() {
    throw UnimplementedError('getProtectionStatus() has not been implemented.');
  }

  /// Retrieves the screen protection capabilities supported by the current
  /// platform and OS version.
  Future<ScreenProtectionCapabilities> getCapabilities() {
    throw UnimplementedError('getCapabilities() has not been implemented.');
  }

  /// Manually displays the native/DOM privacy mask overlay on top of the
  /// application window.
  Future<bool> showPrivacyMask() {
    throw UnimplementedError('showPrivacyMask() has not been implemented.');
  }

  /// Manually hides the native/DOM privacy mask overlay.
  Future<bool> hidePrivacyMask() {
    throw UnimplementedError('hidePrivacyMask() has not been implemented.');
  }

  /// Broadcast stream of real-time [ScreenProtectionEvent] notifications.
  Stream<ScreenProtectionEvent> get onProtectionEvent {
    throw UnimplementedError('onProtectionEvent has not been implemented.');
  }
}

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'xue_hua_screen_protection_method_channel.dart';

abstract class XueHuaScreenProtectionPlatform extends PlatformInterface {
  /// Constructs a XueHuaScreenProtectionPlatform.
  XueHuaScreenProtectionPlatform() : super(token: _token);

  static final Object _token = Object();

  static XueHuaScreenProtectionPlatform _instance = MethodChannelXueHuaScreenProtection();

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

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}

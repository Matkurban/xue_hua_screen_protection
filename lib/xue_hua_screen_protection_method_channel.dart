import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'xue_hua_screen_protection_platform_interface.dart';

/// An implementation of [XueHuaScreenProtectionPlatform] that uses method channels.
class MethodChannelXueHuaScreenProtection extends XueHuaScreenProtectionPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('xue_hua_screen_protection');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}

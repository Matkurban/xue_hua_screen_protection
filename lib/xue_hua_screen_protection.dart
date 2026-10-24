
import 'xue_hua_screen_protection_platform_interface.dart';

class XueHuaScreenProtection {
  Future<String?> getPlatformVersion() {
    return XueHuaScreenProtectionPlatform.instance.getPlatformVersion();
  }
}

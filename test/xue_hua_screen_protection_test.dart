import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection_platform_interface.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockXueHuaScreenProtectionPlatform
    with MockPlatformInterfaceMixin
    implements XueHuaScreenProtectionPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final XueHuaScreenProtectionPlatform initialPlatform = XueHuaScreenProtectionPlatform.instance;

  test('$MethodChannelXueHuaScreenProtection is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelXueHuaScreenProtection>());
  });

  test('getPlatformVersion', () async {
    XueHuaScreenProtection xueHuaScreenProtectionPlugin = XueHuaScreenProtection();
    MockXueHuaScreenProtectionPlatform fakePlatform = MockXueHuaScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = fakePlatform;

    expect(await xueHuaScreenProtectionPlugin.getPlatformVersion(), '42');
  });
}

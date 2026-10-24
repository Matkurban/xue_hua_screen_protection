import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MethodChannelXueHuaScreenProtection platform =
      MethodChannelXueHuaScreenProtection();
  const MethodChannel channel = MethodChannel(
    'com.kurban.xue_hua_screen_protection/methods',
  );

  bool secureState = false;

  setUp(() {
    secureState = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'setSecureScreen':
          final args = methodCall.arguments as Map<Object?, Object?>?;
          secureState = (args?['enabled'] as bool?) ?? false;
          return true;
        case 'isSecureScreenEnabled':
          return secureState;
        case 'configureAppSwitcherProtection':
          return true;
        case 'configureWebProtection':
          return false;
        case 'isScreenBeingRecorded':
          return false;
        case 'getProtectionStatus':
          return <String, dynamic>{
            'isSecureScreenEnabled': secureState,
            'isAppSwitcherMaskEnabled': true,
            'isScreenBeingRecorded': false,
            'isMaskCurrentlyVisible': false,
            'platform': 'android',
          };
        case 'getCapabilities':
          return <String, dynamic>{
            'platform': 'android',
            'osVersion': 'Android 15 (API 35)',
            'supportsHardwareAntiScreenshot': true,
            'supportsHardwareAntiRecording': true,
            'supportsScreenshotDetection': true,
            'supportsRecordingDetection': true,
            'supportsNativeAppSwitcherMask': true,
            'supportsNativeBlurEffect': true,
            'limitations': <String>[],
          };
        case 'showPrivacyMask':
        case 'hidePrivacyMask':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setSecureScreen and isSecureScreenEnabled communicate over MethodChannel',
      () async {
    expect(await platform.setSecureScreen(true), isTrue);
    expect(await platform.isSecureScreenEnabled(), isTrue);

    expect(await platform.setSecureScreen(false), isTrue);
    expect(await platform.isSecureScreenEnabled(), isFalse);
  });

  test('getProtectionStatus and getCapabilities parse channel maps', () async {
    await platform.setSecureScreen(true);
    final status = await platform.getProtectionStatus();
    expect(status.platform, 'android');
    expect(status.isSecureScreenEnabled, isTrue);

    final caps = await platform.getCapabilities();
    expect(caps.platform, 'android');
    expect(caps.supportsHardwareAntiScreenshot, isTrue);
    expect(caps.supportsRecordingDetection, isTrue);
  });

  test('configureAppSwitcherProtection sends serialized config', () async {
    const config = ScreenProtectionMaskConfig(
      enabled: true,
      style: ScreenProtectionMaskStyle.blur,
      blurSigma: 18.0,
    );
    expect(await platform.configureAppSwitcherProtection(config), isTrue);
  });
}

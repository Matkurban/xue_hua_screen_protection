import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PigeonXueHuaScreenProtection platform;
  final MessageCodec<Object?> codec = ScreenProtectionHostApi.pigeonChannelCodec;

  bool secureState = false;
  ScreenProtectionMaskConfigMessage? lastMaskConfig;

  void registerMockPigeonHostHandler(
    String methodName,
    Object? Function(List<Object?>? args) handler,
  ) {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.xue_hua_screen_protection.ScreenProtectionHostApi.$methodName',
      codec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, (Object? message) async {
          final args = message as List<Object?>?;
          final result = handler(args);
          return <Object?>[result];
        });
  }

  void clearMockPigeonHostHandler(String methodName) {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.xue_hua_screen_protection.ScreenProtectionHostApi.$methodName',
      codec,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<Object?>(channel, null);
  }

  const List<String> hostMethods = <String>[
    'setSecureScreen',
    'isSecureScreenEnabled',
    'configureAppSwitcherProtection',
    'configureWebProtection',
    'isScreenBeingRecorded',
    'getProtectionStatus',
    'getCapabilities',
    'showPrivacyMask',
    'hidePrivacyMask',
  ];

  setUp(() {
    secureState = false;
    lastMaskConfig = null;
    platform = PigeonXueHuaScreenProtection();

    registerMockPigeonHostHandler('setSecureScreen', (List<Object?>? args) {
      secureState = (args?[0] as bool?) ?? false;
      return true;
    });
    registerMockPigeonHostHandler(
      'isSecureScreenEnabled',
      (_) => secureState,
    );
    registerMockPigeonHostHandler(
      'configureAppSwitcherProtection',
      (List<Object?>? args) {
        lastMaskConfig = args?[0] as ScreenProtectionMaskConfigMessage?;
        return true;
      },
    );
    registerMockPigeonHostHandler('configureWebProtection', (_) => false);
    registerMockPigeonHostHandler('isScreenBeingRecorded', (_) => false);
    registerMockPigeonHostHandler('getProtectionStatus', (_) {
      return ScreenProtectionStatusMessage(
        isSecureScreenEnabled: secureState,
        isAppSwitcherMaskEnabled: true,
        isScreenBeingRecorded: false,
        isMaskCurrentlyVisible: false,
        platform: 'android',
      );
    });
    registerMockPigeonHostHandler('getCapabilities', (_) {
      return ScreenProtectionCapabilitiesMessage(
        platform: 'android',
        osVersion: 'Android 15 (API 35)',
        supportsHardwareAntiScreenshot: true,
        supportsHardwareAntiRecording: true,
        supportsScreenshotDetection: true,
        supportsRecordingDetection: true,
        supportsNativeAppSwitcherMask: true,
        supportsNativeBlurEffect: true,
        limitations: const <String>[],
      );
    });
    registerMockPigeonHostHandler('showPrivacyMask', (_) => true);
    registerMockPigeonHostHandler('hidePrivacyMask', (_) => true);
  });

  tearDown(() async {
    await platform.dispose();
    for (final method in hostMethods) {
      clearMockPigeonHostHandler(method);
    }
  });

  test(
    'setSecureScreen and isSecureScreenEnabled communicate over Pigeon HostApi',
    () async {
      expect(await platform.setSecureScreen(true), isTrue);
      expect(await platform.isSecureScreenEnabled(), isTrue);

      expect(await platform.setSecureScreen(false), isTrue);
      expect(await platform.isSecureScreenEnabled(), isFalse);
    },
  );

  test(
    'getProtectionStatus and getCapabilities decode Pigeon messages',
    () async {
      await platform.setSecureScreen(true);
      final status = await platform.getProtectionStatus();
      expect(status.platform, 'android');
      expect(status.isSecureScreenEnabled, isTrue);

      final caps = await platform.getCapabilities();
      expect(caps.platform, 'android');
      expect(caps.supportsHardwareAntiScreenshot, isTrue);
      expect(caps.supportsRecordingDetection, isTrue);
    },
  );

  test(
    'configureAppSwitcherProtection encodes ScreenProtectionMaskConfigMessage',
    () async {
      const config = ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.blur,
        blurSigma: 18.0,
        title: 'Pigeon Mask',
      );
      expect(await platform.configureAppSwitcherProtection(config), isTrue);
      expect(lastMaskConfig, isNotNull);
      expect(lastMaskConfig!.enabled, isTrue);
      expect(lastMaskConfig!.style, ScreenProtectionMaskStyleMessage.blur);
      expect(lastMaskConfig!.blurSigma, 18.0);
      expect(lastMaskConfig!.title, 'Pigeon Mask');
    },
  );

  test(
    'ScreenProtectionFlutterApi delivers strongly-typed events to onProtectionEvent stream',
    () async {
      final events = <ScreenProtectionEvent>[];
      final sub = platform.onProtectionEvent.listen(events.add);

      final eventMessage = ScreenProtectionEventMessage(
        type: ScreenProtectionEventTypeMessage.screenshotTaken,
        timestamp: 1700000000000,
        platform: 'android',
        isCaptured: false,
        metadata: <String, Object?>{'source': 'ScreenCaptureCallback_API34'},
      );

      final ByteData? encoded = codec.encodeMessage(<Object?>[eventMessage]);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'dev.flutter.pigeon.xue_hua_screen_protection.ScreenProtectionFlutterApi.onProtectionEvent',
            encoded,
            (_) {},
          );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.type, ScreenProtectionEventType.screenshotTaken);
      expect(events.first.platform, 'android');
      expect(events.first.metadata['source'], 'ScreenCaptureCallback_API34');

      await sub.cancel();
    },
  );
}

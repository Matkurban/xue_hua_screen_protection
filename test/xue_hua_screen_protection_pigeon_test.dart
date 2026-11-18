import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_screen_protection/src/pigeon/messages.g.dart';
import 'package:xue_hua_screen_protection/src/pigeon/pigeon_screen_protection_backend.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PigeonScreenProtectionBackend backend;
  final MessageCodec<Object?> codec = ScreenProtectionHostApi.pigeonChannelCodec;

  bool secureState = false;
  bool maskVisibleState = false;
  ScreenProtectionMaskConfigMessage? lastMaskConfig;
  WebProtectionConfigMessage? lastWebConfig;

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
    maskVisibleState = false;
    lastMaskConfig = null;
    lastWebConfig = null;
    backend = PigeonScreenProtectionBackend();

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
    registerMockPigeonHostHandler(
      'configureWebProtection',
      (List<Object?>? args) {
        lastWebConfig = args?[0] as WebProtectionConfigMessage?;
        return false;
      },
    );
    registerMockPigeonHostHandler('isScreenBeingRecorded', (_) => false);
    registerMockPigeonHostHandler('getProtectionStatus', (_) {
      return ScreenProtectionStatusMessage(
        isSecureScreenEnabled: secureState,
        isAppSwitcherMaskEnabled: lastMaskConfig?.enabled ?? false,
        isScreenBeingRecorded: false,
        isMaskCurrentlyVisible: maskVisibleState,
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
        limitations: const <String>['Note'],
      );
    });
    registerMockPigeonHostHandler('showPrivacyMask', (_) {
      maskVisibleState = true;
      return true;
    });
    registerMockPigeonHostHandler('hidePrivacyMask', (_) {
      maskVisibleState = false;
      return true;
    });
  });

  tearDown(() async {
    await backend.dispose();
    for (final method in hostMethods) {
      clearMockPigeonHostHandler(method);
    }
  });

  test(
    'setSecureScreen and isSecureScreenEnabled communicate over Pigeon HostApi',
    () async {
      expect(await backend.setSecureScreen(true), isTrue);
      expect(await backend.isSecureScreenEnabled(), isTrue);

      expect(await backend.setSecureScreen(false), isTrue);
      expect(await backend.isSecureScreenEnabled(), isFalse);
    },
  );

  test(
    'getProtectionStatus, show/hide mask, and getCapabilities decode Pigeon messages',
    () async {
      await backend.setSecureScreen(true);
      await backend.configureAppSwitcherProtection(
        const ScreenProtectionMaskConfig(),
      );
      expect(await backend.showPrivacyMask(), isTrue);

      final status = await backend.getProtectionStatus();
      expect(status.platform, 'android');
      expect(status.isSecureScreenEnabled, isTrue);
      expect(status.isAppSwitcherMaskEnabled, isTrue);
      expect(status.isMaskCurrentlyVisible, isTrue);

      expect(await backend.hidePrivacyMask(), isTrue);
      expect(await backend.isScreenBeingRecorded(), isFalse);

      final caps = await backend.getCapabilities();
      expect(caps.platform, 'android');
      expect(caps.osVersion, 'Android 15 (API 35)');
      expect(caps.supportsHardwareAntiScreenshot, isTrue);
      expect(caps.supportsRecordingDetection, isTrue);
      expect(caps.limitations, equals(<String>['Note']));
    },
  );

  test(
    'configureAppSwitcherProtection and configureWebProtection encode Pigeon messages',
    () async {
      const config = ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.blur,
        blurSigma: 18.0,
        title: 'Pigeon Mask',
      );
      expect(await backend.configureAppSwitcherProtection(config), isTrue);
      expect(lastMaskConfig, isNotNull);
      expect(lastMaskConfig!.enabled, isTrue);
      expect(lastMaskConfig!.style, ScreenProtectionMaskStyleMessage.blur);
      expect(lastMaskConfig!.blurSigma, 18.0);
      expect(lastMaskConfig!.title, 'Pigeon Mask');

      // Style `none` normalizes `enabled` to false in the Pigeon payload.
      await backend.configureAppSwitcherProtection(
        const ScreenProtectionMaskConfig(
          enabled: true,
          style: ScreenProtectionMaskStyle.none,
        ),
      );
      expect(lastMaskConfig!.enabled, isFalse);

      const webConfig = WebProtectionConfig(
        disableContextMenu: false,
        disablePrint: true,
      );
      expect(await backend.configureWebProtection(webConfig), isFalse);
      expect(lastWebConfig, isNotNull);
      expect(lastWebConfig!.disableContextMenu, isFalse);
      expect(lastWebConfig!.disablePrint, isTrue);
    },
  );

  test(
    'ScreenProtectionFlutterApi delivers strongly-typed events to onProtectionEvent stream',
    () async {
      final events = <ScreenProtectionEvent>[];
      final sub = backend.onProtectionEvent.listen(events.add);

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

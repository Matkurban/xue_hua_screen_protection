import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection_method_channel.dart';

class MockXueHuaScreenProtectionPlatform
    with MockPlatformInterfaceMixin
    implements XueHuaScreenProtectionPlatform {
  bool secureEnabled = false;
  bool maskVisible = false;
  ScreenProtectionMaskConfig maskConfig = const ScreenProtectionMaskConfig();
  WebProtectionConfig webConfig = const WebProtectionConfig();
  final StreamController<ScreenProtectionEvent> eventController =
      StreamController<ScreenProtectionEvent>.broadcast();

  @override
  Future<bool> setSecureScreen(bool enabled) async {
    secureEnabled = enabled;
    return true;
  }

  @override
  Future<bool> isSecureScreenEnabled() async => secureEnabled;

  @override
  Future<bool> configureAppSwitcherProtection(
    ScreenProtectionMaskConfig config,
  ) async {
    maskConfig = config;
    return true;
  }

  @override
  Future<bool> configureWebProtection(WebProtectionConfig config) async {
    webConfig = config;
    return true;
  }

  @override
  Future<bool> isScreenBeingRecorded() async => false;

  @override
  Future<ScreenProtectionStatus> getProtectionStatus() async {
    return ScreenProtectionStatus(
      isSecureScreenEnabled: secureEnabled,
      isAppSwitcherMaskEnabled:
          maskConfig.enabled && maskConfig.style != ScreenProtectionMaskStyle.none,
      isScreenBeingRecorded: false,
      isMaskCurrentlyVisible: maskVisible,
      platform: 'macos',
    );
  }

  @override
  Future<ScreenProtectionCapabilities> getCapabilities() async {
    return const ScreenProtectionCapabilities(
      platform: 'macos',
      osVersion: 'macOS 15.0',
      supportsHardwareAntiScreenshot: true,
      supportsHardwareAntiRecording: true,
      supportsScreenshotDetection: true,
      supportsRecordingDetection: true,
      supportsNativeAppSwitcherMask: true,
      supportsNativeBlurEffect: true,
      limitations: <String>['Test note'],
    );
  }

  @override
  Future<bool> showPrivacyMask() async {
    maskVisible = true;
    return true;
  }

  @override
  Future<bool> hidePrivacyMask() async {
    maskVisible = false;
    return true;
  }

  @override
  Stream<ScreenProtectionEvent> get onProtectionEvent =>
      eventController.stream;
}

void main() {
  final XueHuaScreenProtectionPlatform initialPlatform =
      XueHuaScreenProtectionPlatform.instance;

  test('$MethodChannelXueHuaScreenProtection is the default instance', () {
    expect(
      initialPlatform,
      isInstanceOf<MethodChannelXueHuaScreenProtection>(),
    );
  });

  test('enableSecureScreen and disableSecureScreen toggle state', () async {
    final mockPlatform = MockXueHuaScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = mockPlatform;
    const plugin = XueHuaScreenProtection.instance;

    expect(await plugin.enableSecureScreen(), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isTrue);

    expect(await plugin.disableSecureScreen(), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isFalse);
  });

  test('configureAppSwitcherProtection and status serialization work', () async {
    final mockPlatform = MockXueHuaScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = mockPlatform;
    const plugin = XueHuaScreenProtection.instance;

    const config = ScreenProtectionMaskConfig(
      enabled: true,
      style: ScreenProtectionMaskStyle.solidColor,
      blurSigma: 25.0,
      title: 'Vault Locked',
    );

    expect(await plugin.configureAppSwitcherProtection(config), isTrue);
    expect(mockPlatform.maskConfig, equals(config));

    await plugin.showPrivacyMask();
    final status = await plugin.getProtectionStatus();
    expect(status.isMaskCurrentlyVisible, isTrue);
    expect(status.isAppSwitcherMaskEnabled, isTrue);
  });

  test('onScreenCaptured and onScreenRecordingChanged filter events', () async {
    final mockPlatform = MockXueHuaScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = mockPlatform;
    const plugin = XueHuaScreenProtection.instance;

    final capturedEvents = <ScreenProtectionEvent>[];
    final recordingStates = <bool>[];

    final sub1 = plugin.onScreenCaptured.listen(capturedEvents.add);
    final sub2 = plugin.onScreenRecordingChanged.listen(recordingStates.add);

    mockPlatform.eventController.add(
      ScreenProtectionEvent(
        type: ScreenProtectionEventType.screenshotTaken,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        platform: 'ios',
      ),
    );
    mockPlatform.eventController.add(
      ScreenProtectionEvent(
        type: ScreenProtectionEventType.recordingStarted,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        platform: 'ios',
        isCaptured: true,
      ),
    );
    mockPlatform.eventController.add(
      ScreenProtectionEvent(
        type: ScreenProtectionEventType.recordingStopped,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000002000),
        platform: 'ios',
        isCaptured: false,
      ),
    );

    await Future<void>.delayed(Duration.zero);

    expect(capturedEvents, hasLength(1));
    expect(capturedEvents.first.type, ScreenProtectionEventType.screenshotTaken);
    expect(recordingStates, equals(<bool>[true, false]));

    await sub1.cancel();
    await sub2.cancel();
  });

  testWidgets('ScreenProtectionWatermark and ScreenProtectionScope render cleanly',
      (WidgetTester tester) async {
    final mockPlatform = MockXueHuaScreenProtectionPlatform();
    XueHuaScreenProtectionPlatform.instance = mockPlatform;

    await tester.pumpWidget(
      const MaterialApp(
        home: ScreenProtectionScope(
          enableSecureScreen: true,
          watermarkText: 'CONFIDENTIAL',
          watermarkSubText: 'USER-01',
          child: Scaffold(
            body: Text('Secret Document'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Secret Document'), findsOneWidget);
    expect(mockPlatform.secureEnabled, isTrue);
  });
}

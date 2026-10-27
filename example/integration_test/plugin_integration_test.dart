import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

/// Host-platform API coverage. Full UI automation lives in
/// `test_driver/app_test.dart` (Flutter Driver).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final plugin = XueHuaScreenProtection.instance;

  testWidgets('capabilities and secure screen round-trip', (
    WidgetTester tester,
  ) async {
    final capabilities = await plugin.getCapabilities();
    expect(capabilities.platform.isNotEmpty, isTrue);
    if (!kIsWeb && Platform.isLinux) {
      expect(capabilities.platform, 'linux');
      expect(capabilities.supportsHardwareAntiScreenshot, isFalse);
      expect(capabilities.supportsNativeAppSwitcherMask, isTrue);
      expect(capabilities.limitations, isNotEmpty);
    }
    if (!kIsWeb && Platform.isMacOS) {
      expect(capabilities.platform, 'macos');
      expect(capabilities.supportsHardwareAntiScreenshot, isTrue);
      expect(capabilities.supportsHardwareAntiRecording, isTrue);
      expect(capabilities.supportsScreenshotDetection, isTrue);
      expect(capabilities.supportsRecordingDetection, isTrue);
      expect(capabilities.supportsNativeAppSwitcherMask, isTrue);
      expect(capabilities.supportsNativeBlurEffect, isTrue);
    }
    if (!kIsWeb && Platform.isIOS) {
      expect(capabilities.platform, 'ios');
      expect(capabilities.supportsHardwareAntiScreenshot, isTrue);
      expect(capabilities.supportsHardwareAntiRecording, isTrue);
      expect(capabilities.supportsScreenshotDetection, isTrue);
      expect(capabilities.supportsRecordingDetection, isTrue);
      expect(capabilities.supportsNativeAppSwitcherMask, isTrue);
      expect(capabilities.supportsNativeBlurEffect, isTrue);
    }

    if (!kIsWeb && Platform.isAndroid) {
      expect(capabilities.platform, 'android');
      expect(capabilities.supportsHardwareAntiScreenshot, isTrue);
      expect(capabilities.supportsHardwareAntiRecording, isTrue);
      expect(capabilities.supportsScreenshotDetection, isTrue);
      expect(capabilities.supportsRecordingDetection, isTrue);
      expect(capabilities.supportsNativeAppSwitcherMask, isTrue);
      final apiMatch = RegExp(r'API (\d+)').firstMatch(capabilities.osVersion);
      expect(apiMatch, isNotNull);
      final api = int.parse(apiMatch!.group(1)!);
      expect(capabilities.supportsNativeBlurEffect, api >= 31);
      if (api < 34) {
        expect(capabilities.limitations, isNotEmpty);
      }
    }

    expect(await plugin.enableSecureScreen(), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isTrue);
    var status = await plugin.getProtectionStatus();
    expect(status.isSecureScreenEnabled, isTrue);
    expect(status.platform, capabilities.platform);

    if (!kIsWeb && Platform.isLinux) {
      // Linux secure-screen fallback should keep focus-out masking armed.
      expect(status.isAppSwitcherMaskEnabled, isTrue);
    }

    expect(await plugin.disableSecureScreen(), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isFalse);
    status = await plugin.getProtectionStatus();
    expect(status.isSecureScreenEnabled, isFalse);
  });

  testWidgets('app-switcher mask configure + show/hide privacy mask', (
    WidgetTester tester,
  ) async {
    final configured = await plugin.configureAppSwitcherProtection(
      const ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.solidColor,
        blurSigma: 12,
        title: 'Driver Mask',
        subtitle: 'integration',
        showLockIcon: true,
        protectOnWindowBlur: true,
      ),
    );
    expect(configured, isTrue);

    expect(await plugin.showPrivacyMask(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    var status = await plugin.getProtectionStatus();
    expect(status.isMaskCurrentlyVisible, isTrue);
    expect(status.isAppSwitcherMaskEnabled, isTrue);

    expect(await plugin.hidePrivacyMask(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    status = await plugin.getProtectionStatus();
    expect(status.isMaskCurrentlyVisible, isFalse);

    final events = <ScreenProtectionEvent>[];
    final sub = plugin.onProtectionEvent.listen(events.add);
    await plugin.showPrivacyMask();
    await tester.pump(const Duration(milliseconds: 300));
    await plugin.hidePrivacyMask();
    await tester.pump(const Duration(milliseconds: 300));
    await sub.cancel();
    expect(
      events.any((e) => e.type == ScreenProtectionEventType.maskShown),
      isTrue,
    );
    expect(
      events.any((e) => e.type == ScreenProtectionEventType.maskHidden),
      isTrue,
    );
  });

  testWidgets('web protection is no-op on native hosts', (
    WidgetTester tester,
  ) async {
    final result = await plugin.configureWebProtection(
      const WebProtectionConfig(
        disableContextMenu: true,
        disablePrint: true,
        interceptCaptureShortcuts: true,
      ),
    );
    if (kIsWeb) {
      expect(result, isTrue);
    } else {
      expect(result, isFalse);
    }
    expect(await plugin.isScreenBeingRecorded(), isFalse);
  });

  testWidgets('setSecureScreen direct toggle and blur mask config', (
    WidgetTester tester,
  ) async {
    expect(await plugin.setSecureScreen(true), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isTrue);

    final blurConfigured = await plugin.configureAppSwitcherProtection(
      const ScreenProtectionMaskConfig(
        enabled: true,
        style: ScreenProtectionMaskStyle.blur,
        blurSigma: 24,
        title: 'Blur Mask',
        subtitle: 'integration blur',
        showLockIcon: true,
        protectOnWindowBlur: true,
      ),
    );
    expect(blurConfigured, isTrue);

    expect(await plugin.showPrivacyMask(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    var status = await plugin.getProtectionStatus();
    expect(status.isMaskCurrentlyVisible, isTrue);
    expect(status.isAppSwitcherMaskEnabled, isTrue);
    expect(status.isSecureScreenEnabled, isTrue);

    expect(await plugin.hidePrivacyMask(), isTrue);
    expect(await plugin.setSecureScreen(false), isTrue);
    expect(await plugin.isSecureScreenEnabled(), isFalse);
    status = await plugin.getProtectionStatus();
    expect(status.isSecureScreenEnabled, isFalse);
    expect(status.isMaskCurrentlyVisible, isFalse);
  });

  testWidgets('ScreenProtectionWatermark and Scope smoke mount', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScreenProtectionWatermark(
            text: 'IT-USER',
            subText: 'integration',
            child: Text('watermark-child', key: ValueKey('watermark_child')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('watermark_child')), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: ScreenProtectionScope(
          enableSecureScreen: true,
          watermarkText: 'SCOPE',
          watermarkSubText: 'smoke',
          child: Scaffold(
            body: Text('scope-child', key: ValueKey('scope_child')),
          ),
        ),
      ),
    );
    await tester.pump(); // first frame
    await tester.pump(const Duration(milliseconds: 300)); // post-frame config
    expect(find.byKey(const ValueKey('scope_child')), findsOneWidget);

    // Scope enables secure screen after post-frame callback.
    expect(await plugin.isSecureScreenEnabled(), isTrue);

    // Unmount to restore (dispose path).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
  });
}

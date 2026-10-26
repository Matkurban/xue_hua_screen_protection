import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

/// End-to-end Flutter Driver suite for the example dashboard.
void main() {
  late FlutterDriver driver;

  setUpAll(() async {
    driver = await FlutterDriver.connect();
    await driver.waitUntilFirstFrameRasterized();
    await driver.requestData('hide_mask');
    await driver.requestData('configure_mask_off');
    await driver.requestData('disable_secure');
  });

  tearDownAll(() async {
    try {
      await driver.requestData('hide_mask');
      await driver.requestData('configure_mask_off');
      await driver.requestData('disable_secure');
    } catch (_) {}
    await driver.close();
  });

  Future<Map<String, dynamic>> requestJson(String command) async {
    final raw = await driver.requestData(command);
    expect(raw, isNotEmpty, reason: 'empty response for $command');
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> readStatus() => requestJson('get_status');

  Future<void> waitUntil(
    bool Function(Map<String, dynamic> status) predicate, {
    String label = 'condition',
    int tries = 50,
  }) async {
    for (var i = 0; i < tries; i++) {
      final status = await readStatus();
      if (predicate(status)) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    fail('Timed out waiting for $label; last=${await readStatus()}');
  }

  Future<void> resetProtection() async {
    await requestJson('hide_mask');
    await requestJson('configure_mask_off');
    await requestJson('disable_secure');
    await waitUntil(
      (s) =>
          s['isSecureScreenEnabled'] == false &&
          s['isMaskCurrentlyVisible'] == false,
      label: 'protection reset',
    );
  }

  test('home dashboard loads with platform capabilities', () async {
    await driver.waitFor(find.text('XueHua Screen Protection'));
    await driver.waitFor(find.text('Confidential Treasury Vault'));
    await driver.waitFor(find.text('1. Anti-Screenshot & Anti-Recording'));
    await driver.waitFor(find.byValueKey('enable_protection_button'));
    await driver.waitFor(find.byValueKey('disable_protection_button'));
    await driver.waitFor(find.byValueKey('preview_mask_button'));
    await driver.waitFor(find.byValueKey('secure_screen_switch'));
    await driver.waitFor(find.byValueKey('scoped_vault_button'));

    final status = await readStatus();
    expect(status['platform'], isNotEmpty);
    final caps = await requestJson('get_capabilities');
    expect(caps['platform'], status['platform']);
    if (Platform.isLinux) {
      expect(status['platform'], 'linux');
      expect(caps['supportsHardwareAntiScreenshot'], isFalse);
      expect(caps['supportsHardwareAntiRecording'], isFalse);
      expect(caps['supportsScreenshotDetection'], isFalse);
      expect(caps['supportsRecordingDetection'], isFalse);
      expect(caps['supportsNativeAppSwitcherMask'], isTrue);
      expect((caps['limitations'] as List).isNotEmpty, isTrue);
    }
    if (Platform.isWindows) {
      expect(status['platform'], 'windows');
      expect(caps['supportsHardwareAntiScreenshot'], isTrue);
      expect(caps['supportsHardwareAntiRecording'], isTrue);
      expect(caps['supportsNativeAppSwitcherMask'], isTrue);
    }
  });

  test('UI buttons enable and disable secure screen', () async {
    await resetProtection();
    await driver.tap(find.byValueKey('enable_protection_button'));
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == true,
      label: 'secure enabled via Enable button',
    );
    if (Platform.isLinux) {
      expect((await readStatus())['isAppSwitcherMaskEnabled'], isTrue);
    }

    await driver.tap(find.byValueKey('disable_protection_button'));
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == false,
      label: 'secure disabled via Disable button',
    );
  });

  test('secure screen switch tile toggles protection', () async {
    await resetProtection();
    await driver.tap(find.byValueKey('secure_screen_switch'));
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == true,
      label: 'secure enabled via switch',
    );
    await driver.tap(find.byValueKey('secure_screen_switch'));
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == false,
      label: 'secure disabled via switch',
    );
  });

  test('preview privacy mask button shows then hides overlay', () async {
    await resetProtection();
    await requestJson('configure_mask_on');
    await driver.tap(find.byValueKey('preview_mask_button'));
    await waitUntil(
      (s) => s['isMaskCurrentlyVisible'] == true,
      label: 'mask visible after preview',
    );
    await waitUntil(
      (s) => s['isMaskCurrentlyVisible'] == false,
      label: 'mask hidden after preview window',
      tries: 60,
    );
    await requestJson('configure_mask_off');
    await requestJson('hide_mask');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('scoped vault page opens via ScreenProtectionScope', () async {
    await resetProtection();
    // Use data-handler navigation (zero-duration route). A Driver tap that both
    // pushes a route and arms Linux secure-screen fallbacks can deadlock frame
    // sync under xvfb; the button itself is still asserted on the home page.
    await driver.waitFor(find.byValueKey('scoped_vault_button'));
    final opened = await requestJson('open_scoped_vault');
    expect(opened['ok'], isTrue);
    await driver.waitFor(find.byValueKey('scoped_vault_page'));
    await driver.waitFor(find.text('Protected by ScreenProtectionScope'));
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == true,
      label: 'secure enabled by ScreenProtectionScope',
    );
    final popped = await requestJson('pop_route');
    expect(popped['ok'], isTrue);
    await driver.waitFor(find.text('XueHua Screen Protection'));
    await driver.waitFor(find.byValueKey('scoped_vault_button'));
    await resetProtection();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('configure app-switcher mask on and off', () async {
    final off = await requestJson('configure_mask_off');
    expect(off['ok'], isTrue);
    await waitUntil(
      (s) => s['isAppSwitcherMaskEnabled'] == false,
      label: 'mask config disabled',
    );
    final on = await requestJson('configure_mask_on');
    expect(on['ok'], isTrue);
    await waitUntil(
      (s) => s['isAppSwitcherMaskEnabled'] == true,
      label: 'mask config enabled',
    );
    await requestJson('configure_mask_off');
  });

  test('privacy mask show/hide via driver data handler', () async {
    await requestJson('configure_mask_on');
    final shown = await requestJson('show_mask');
    expect(shown['ok'], isTrue);
    await waitUntil(
      (s) => s['isMaskCurrentlyVisible'] == true,
      label: 'mask visible via handler',
    );
    final hidden = await requestJson('hide_mask');
    expect(hidden['ok'], isTrue);
    await waitUntil(
      (s) => s['isMaskCurrentlyVisible'] == false,
      label: 'mask hidden via handler',
    );
    await requestJson('configure_mask_off');
  });

  test('web protection configure returns native-host result', () async {
    final web = await requestJson('configure_web');
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      expect(web['ok'], isFalse);
    }
  });

  test('direct enable/disable secure via data handler', () async {
    final enabled = await requestJson('enable_secure');
    expect(enabled['ok'], isTrue);
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == true,
      label: 'secure via handler enable',
    );
    final disabled = await requestJson('disable_secure');
    expect(disabled['ok'], isTrue);
    await waitUntil(
      (s) => s['isSecureScreenEnabled'] == false,
      label: 'secure via handler disable',
    );
  });
}

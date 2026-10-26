import 'dart:convert';

import 'package:flutter_driver/driver_extension.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';
import 'package:xue_hua_screen_protection_example/main.dart' as app;

/// Driver entrypoint with a data handler for reliable plugin status reads.
void main() {
  enableFlutterDriverExtension(
    handler: (String? message) async {
      final plugin = XueHuaScreenProtection.instance;
      switch (message) {
        case 'get_status':
          final status = await plugin.getProtectionStatus();
          return jsonEncode(status.toMap());
        case 'get_capabilities':
          final caps = await plugin.getCapabilities();
          return jsonEncode(<String, Object?>{
            'platform': caps.platform,
            'osVersion': caps.osVersion,
            'supportsHardwareAntiScreenshot':
                caps.supportsHardwareAntiScreenshot,
            'supportsHardwareAntiRecording':
                caps.supportsHardwareAntiRecording,
            'supportsScreenshotDetection': caps.supportsScreenshotDetection,
            'supportsRecordingDetection': caps.supportsRecordingDetection,
            'supportsNativeAppSwitcherMask':
                caps.supportsNativeAppSwitcherMask,
            'supportsNativeBlurEffect': caps.supportsNativeBlurEffect,
            'limitations': caps.limitations,
          });
        case 'enable_secure':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.enableSecureScreen(),
          });
        case 'disable_secure':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.disableSecureScreen(),
          });
        case 'show_mask':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.showPrivacyMask(),
          });
        case 'hide_mask':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.hidePrivacyMask(),
          });
        case 'configure_mask_on':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.configureAppSwitcherProtection(
              const ScreenProtectionMaskConfig(
                enabled: true,
                style: ScreenProtectionMaskStyle.blur,
                protectOnWindowBlur: true,
              ),
            ),
          });
        case 'configure_mask_off':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.configureAppSwitcherProtection(
              const ScreenProtectionMaskConfig.disabled(),
            ),
          });
        case 'configure_web':
          return jsonEncode(<String, Object?>{
            'ok': await plugin.configureWebProtection(
              const WebProtectionConfig(),
            ),
          });
        case 'open_scoped_vault':
          return jsonEncode(<String, Object?>{
            'ok': app.openScopedVaultFromDriver(),
          });
        case 'pop_route':
          return jsonEncode(<String, Object?>{
            'ok': app.popRouteFromDriver(),
          });
        default:
          return '';
      }
    },
  );
  app.main();
}

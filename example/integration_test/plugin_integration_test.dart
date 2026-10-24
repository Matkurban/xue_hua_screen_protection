import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xue_hua_screen_protection/xue_hua_screen_protection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enableSecureScreen and getCapabilities integration test', (
    WidgetTester tester,
  ) async {
    final plugin = XueHuaScreenProtection.instance;
    final enabled = await plugin.enableSecureScreen();
    expect(enabled, isTrue);

    final status = await plugin.getProtectionStatus();
    expect(status.isSecureScreenEnabled, isTrue);

    final capabilities = await plugin.getCapabilities();
    expect(capabilities.platform.isNotEmpty, isTrue);

    await plugin.disableSecureScreen();
  });
}

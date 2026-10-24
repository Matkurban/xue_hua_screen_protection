import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xue_hua_screen_protection_example/main.dart';

void main() {
  testWidgets('ScreenProtectionDemoApp renders all control sections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ScreenProtectionDemoApp());
    await tester.pump();

    expect(find.text('XueHua Screen Protection'), findsOneWidget);
    expect(find.text('Confidential Treasury Vault'), findsOneWidget);
    expect(find.textContaining('Anti-Screenshot'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
  });
}

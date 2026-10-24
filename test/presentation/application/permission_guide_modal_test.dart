import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/application/widgets/permission_guide_modal.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('PermissionGuideModal Tests', () {
    testWidgets('renders 4-step walkthrough and calls openAccessibilitySettings', (tester) async {
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PermissionGuideModal.show(
                  context,
                  platformChannel: platform,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Aktivasi Layanan Aksesibilitas'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Buka Pengaturan Aksesibilitas'), findsOneWidget);

      await tester.tap(find.text('Buka Pengaturan Aksesibilitas'));
      await tester.pumpAndSettle();

      expect(platform.openSettingsCalled, isTrue);
      expect(find.byType(PermissionGuideModal), findsNothing);
    });

    testWidgets('Nanti Saja button dismisses modal', (tester) async {
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PermissionGuideModal.show(
                  context,
                  platformChannel: platform,
                ),
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nanti Saja'));
      await tester.pumpAndSettle();

      expect(find.byType(PermissionGuideModal), findsNothing);
    });
  });
}

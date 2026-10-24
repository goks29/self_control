import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('MainScaffold Navigation Shell', () {
    testWidgets('renders BottomNavigationBar and switches between Dashboard and Apps', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Beranda'), findsWidgets);
      expect(find.text('Aplikasi'), findsWidgets);

      await tester.tap(find.text('Aplikasi').last);
      await tester.pumpAndSettle();

      expect(find.text('Pilih Aplikasi'), findsOneWidget);
    });

    testWidgets('opens Drawer and navigates to Settings', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final settingsRepo = FakeSettingsRepository();
      final platform = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        MaterialApp(
          home: MainScaffold(
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            settingsRepository: settingsRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Self-Control'), findsOneWidget);
      expect(find.text('Fokus & Disiplin Digital'), findsOneWidget);
      expect(find.text('Pengaturan'), findsOneWidget);

      await tester.tap(find.text('Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });
}

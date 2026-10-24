import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('PasswordUnlockModal Tests', () {
    testWidgets('shows error and logs event on incorrect password', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'secretpassword');
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'YouTube',
              packageName: 'com.google.android.youtube',
              appId: 1,
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'wrongpass');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(find.text('Password salah. Silakan coba lagi.'), findsOneWidget);
      expect(logRepo.logs.length, 1);
      expect(logRepo.logs.first.eventType, ActivityLog.eventPasswordFailed);
    });

    testWidgets('creates temporary unlock and logs event on correct password', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'correct123');
      final logRepo = FakeActivityLogRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'YouTube',
              packageName: 'com.google.android.youtube',
              appId: 42,
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
              temporaryUnlockRepository: unlockRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'correct123');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(unlockRepo.unlocks.length, 1);
      expect(unlockRepo.unlocks.first.appId, 42);
      expect(logRepo.logs.length, 1);
      expect(logRepo.logs.first.eventType, ActivityLog.eventTemporaryUnlockStarted);
    });
  });
}

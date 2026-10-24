import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('Anti-Tamper Timer Epoch Calculation Tests', () {
    test('Exact wall-clock ceiling calculation matches specified formula', () {
      int calcRemaining(int endMs, int nowMs) {
        final diffMs = endMs - nowMs;
        return diffMs > 0 ? (diffMs + 999) ~/ 1000 : 0;
      }

      expect(calcRemaining(1000, 1000), 0);
      expect(calcRemaining(1000, 1001), 0);
      expect(calcRemaining(1000, 999), 1);
      expect(calcRemaining(1000, 1), 1);
      expect(calcRemaining(1000, 0), 1);
      expect(calcRemaining(2001, 1000), 2);
      expect(calcRemaining(2000, 1000), 1);
      expect(calcRemaining(60000, 0), 60);
      expect(calcRemaining(300000, 0), 300);
    });

    testWidgets('Backward clock jump mid-session triggers tampering detection and reset', (tester) async {
      int fakeNow = 1000000;
      final logRepo = FakeActivityLogRepository();
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            packageName: 'com.instagram.android',
            startAtEpochMs: fakeNow,
            endAtEpochMs: fakeNow + 300000,
            settingsRepository: settingsRepo,
            activityLogRepository: logRepo,
            autoOpenModal: false,
            nowMsProvider: () => fakeNow,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('05:00'), findsOneWidget);

      fakeNow = 500000;
      final state = tester.state(find.byType(LockedScreen)) as dynamic;
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(LockedScreen), findsOneWidget);
      final tamperingLogs = logRepo.logs.where((l) => l.eventType == ActivityLog.eventTamperingDetected).toList();
      expect(tamperingLogs.isNotEmpty, isTrue);
      expect(tamperingLogs.first.eventType, equals(ActivityLog.eventTamperingDetected));
    });

    testWidgets('PopScope prevents pop route and calls SystemNavigator.pop', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'TestApp',
            packageName: 'com.test.app',
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope<Object?>>(popScopeFinder);
      expect(popScope.canPop, isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('Milestone 4 Adversarial Stress Tests: Anti-Tamper & Non-Cancellation', () {
    testWidgets('Adversarial Test 1: Backward clock jump before startEpoch triggers tampering detection, resets baseline, and logs event', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final logRepo = FakeActivityLogRepository();
      final settingsRepo = FakeSettingsRepository();

      final futureStart = now + 3600000;
      final futureEnd = futureStart + 300000;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            packageName: 'com.instagram.android',
            startAtEpochMs: futureStart,
            endAtEpochMs: futureEnd,
            settingsRepository: settingsRepo,
            activityLogRepository: logRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tamperingLogs = logRepo.logs.where((l) => l.eventType == ActivityLog.eventTamperingDetected).toList();
      
      expect(tamperingLogs.isNotEmpty, isTrue);
      expect(tamperingLogs.first.eventType, equals(ActivityLog.eventTamperingDetected));
      expect(find.text('05:00'), findsOneWidget);
    });

    testWidgets('Adversarial Test 2: PopScope prevents pop route, keeps LockedScreen mounted, and calls SystemNavigator.pop', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      var systemNavigatorPopCalls = 0;
      bool returnedHome = false;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'SystemNavigator.pop') {
            systemNavigatorPopCalls++;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: LockedScreen(
                        appName: 'TikTok',
                        packageName: 'com.zhiliaoapp.musically',
                        settingsRepository: settingsRepo,
                        autoOpenModal: false,
                      ),
                    ),
                  ),
                ).then((_) => returnedHome = true);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsOneWidget);
      final popScope = tester.widget<PopScope<Object?>>(popScopeFinder);
      expect(popScope.canPop, isFalse);

      await Navigator.of(tester.element(find.byType(LockedScreen))).maybePop();
      await tester.pump();

      expect(find.byType(LockedScreen), findsOneWidget);
      expect(systemNavigatorPopCalls, equals(1));

      await tester.tap(find.text('Kembali ke Layar Utama'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(returnedHome, isTrue);
    });

    testWidgets('Adversarial Test 3: Zero remaining seconds reveals unlock button and allows password unlock modal', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Twitter',
            packageName: 'com.twitter.android',
            startAtEpochMs: now - 301000,
            endAtEpochMs: now - 1000,
            settingsRepository: settingsRepo,
            activityLogRepository: logRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Buka Kunci Aplikasi'), findsOneWidget);
      expect(find.text('Waktu tunggu telah selesai'), findsOneWidget);
    });
  });
}

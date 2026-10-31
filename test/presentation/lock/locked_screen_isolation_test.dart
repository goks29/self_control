import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/repositories/block_session_repository.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  late BlockSessionRepository sessionRepository;

  setUp(() {
    sessionRepository = FakeBlockSessionRepository();
  });

  group('LockedScreen Countdown Timer & Session Isolation Tests', () {
    testWidgets('isolates countdown timer across package switches without timer leakage or reset', (tester) async {
      int fakeNow = 1000000000;
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'waiting_duration_seconds': '300',
        },
      );

      final t0 = fakeNow;

      await sessionRepository.createSession(
        BlockSession(
          packageName: 'com.app.a',
          startAt: DateTime.fromMillisecondsSinceEpoch(t0 - 60000),
          endAt: DateTime.fromMillisecondsSinceEpoch(t0 + 240000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(t0 - 60000),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.app.a',
            appName: 'Application A',
            settingsRepository: settingsRepo,
            blockSessionRepository: sessionRepository,
            nowMsProvider: () => fakeNow,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Application A'), findsOneWidget);
      expect(find.text('04:00'), findsOneWidget);

      final sessionAInitial = await sessionRepository.getActiveSessionForPackage('com.app.a');
      expect(sessionAInitial, isNotNull);
      expect(sessionAInitial!.startAt.millisecondsSinceEpoch, equals(t0 - 60000));

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.app.b',
            appName: 'Application B',
            settingsRepository: settingsRepo,
            blockSessionRepository: sessionRepository,
            nowMsProvider: () => fakeNow,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Application B'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('04:00'), findsNothing);

      final sessionBInitial = await sessionRepository.getActiveSessionForPackage('com.app.b');
      expect(sessionBInitial, isNotNull);
      expect(sessionBInitial!.startAt.millisecondsSinceEpoch, equals(t0));

      fakeNow = t0 + 1000;
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('04:59'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.app.a',
            appName: 'Application A',
            settingsRepository: settingsRepo,
            blockSessionRepository: sessionRepository,
            nowMsProvider: () => fakeNow,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Application A'), findsOneWidget);
      expect(find.text('03:59'), findsOneWidget);
      expect(find.text('05:00'), findsNothing);
      expect(find.text('04:59'), findsNothing);

      final sessionARechecked = await sessionRepository.getActiveSessionForPackage('com.app.a');
      expect(sessionARechecked, isNotNull);
      expect(sessionARechecked!.startAt.millisecondsSinceEpoch, equals(t0 - 60000));
    });

    testWidgets('didUpdateWidget seamlessly transitions state and reloads package session', (tester) async {
      int fakeNow = 2000000000;
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {'waiting_duration_seconds': '300'},
      );
      final t0 = fakeNow;

      await sessionRepository.createSession(
        BlockSession(
          packageName: 'com.existing.app',
          startAt: DateTime.fromMillisecondsSinceEpoch(t0 - 120000),
          endAt: DateTime.fromMillisecondsSinceEpoch(t0 + 180000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(t0 - 120000),
        ),
      );

      final notifier = ValueNotifier<String>('com.new.app');

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: notifier,
            builder: (context, currentPkg, _) {
              return LockedScreen(
                packageName: currentPkg,
                appName: currentPkg == 'com.new.app' ? 'New App' : 'Existing App',
                settingsRepository: settingsRepo,
                blockSessionRepository: sessionRepository,
                nowMsProvider: () => fakeNow,
                autoOpenModal: false,
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('New App'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);

      notifier.value = 'com.existing.app';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Existing App'), findsOneWidget);
      expect(find.text('03:00'), findsOneWidget);

      notifier.value = 'com.new.app';
      fakeNow += 30000;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('New App'), findsOneWidget);
      expect(find.text('04:30'), findsOneWidget);
    });
  });
}

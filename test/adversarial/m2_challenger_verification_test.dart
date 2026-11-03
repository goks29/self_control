import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/repositories/block_session_repository.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';

import '../presentation/test_helpers.dart';

class FailingBlockSessionRepository extends FakeBlockSessionRepository {
  bool fail = true;
  int loadAttempts = 0;

  @override
  Future<int> createSession(BlockSession session) async {
    if (fail) throw Exception('Simulated DB disk failure');
    return super.createSession(session);
  }

  @override
  Future<void> completeActiveSessionsForPackage(String packageName) async {
    throw Exception('Simulated DB disk failure');
  }

  @override
  Future<BlockSession?> getActiveSession() async {
    throw Exception('Simulated DB disk failure');
  }

  @override
  Future<BlockSession?> getActiveSessionForPackage(String packageName) async {
    loadAttempts++;
    if (fail) throw Exception('Simulated DB disk failure');
    return super.getActiveSessionForPackage(packageName);
  }

  @override
  Future<List<BlockSession>> getScheduledSessions() async {
    throw Exception('Simulated DB disk failure');
  }

  @override
  Future<void> updateSessionStatus(int sessionId, String status) async {
    throw Exception('Simulated DB disk failure');
  }
}

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

  group('M2 Empirical Challenger State Isolation & Switching Tests', () {
    testWidgets(
      'switching A (240s) -> B (300s) -> A resumes real wall-clock elapsed time',
      (tester) async {
        int simulatedNowMs = 1700000000000;
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '300'},
        );

        final t0 = simulatedNowMs;

        await sessionRepository.createSession(
          BlockSession(
            packageName: 'com.app.alpha',
            startAt: DateTime.fromMillisecondsSinceEpoch(t0 - 60000),
            endAt: DateTime.fromMillisecondsSinceEpoch(t0 + 240000),
            status: BlockSession.statusActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(t0 - 60000),
          ),
        );

        final pkgNotifier = ValueNotifier<String>('com.app.alpha');

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String>(
              valueListenable: pkgNotifier,
              builder: (context, pkg, _) {
                return LockedScreen(
                  key: const ValueKey('locked_screen_key'),
                  packageName: pkg,
                  appName: pkg == 'com.app.alpha' ? 'Alpha App' : 'Beta App',
                  settingsRepository: settingsRepo,
                  blockSessionRepository: sessionRepository,
                  nowMsProvider: () => simulatedNowMs,
                  autoOpenModal: false,
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Alpha App'), findsOneWidget);
        expect(find.text('04:00'), findsOneWidget);

        pkgNotifier.value = 'com.app.beta';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Beta App'), findsOneWidget);
        expect(find.text('05:00'), findsOneWidget);
        expect(find.text('04:00'), findsNothing);

        final sessionBeta = await sessionRepository.getActiveSessionForPackage(
          'com.app.beta',
        );
        expect(sessionBeta, isNotNull);
        expect(sessionBeta!.startAt.millisecondsSinceEpoch, equals(t0));
        expect(sessionBeta.endAt.millisecondsSinceEpoch, equals(t0 + 300000));

        simulatedNowMs += 1000;
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('04:59'), findsOneWidget);

        simulatedNowMs = t0 + 30000;
        pkgNotifier.value = 'com.app.alpha';
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Alpha App'), findsOneWidget);
        expect(find.text('03:30'), findsOneWidget);
        expect(find.text('04:59'), findsNothing);
        expect(find.text('05:00'), findsNothing);
      },
    );

    testWidgets(
      'rapid sequential lock switching across 5 distinct packages maintains independent state',
      (tester) async {
        int simulatedNowMs = 1750000000000;
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '300'},
        );

        final packages = [
          'com.pkg.one',
          'com.pkg.two',
          'com.pkg.three',
          'com.pkg.four',
          'com.pkg.five',
        ];

        final pkgNotifier = ValueNotifier<String>(packages[0]);

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String>(
              valueListenable: pkgNotifier,
              builder: (context, pkg, _) {
                return LockedScreen(
                  key: const ValueKey('locked_screen_key'),
                  packageName: pkg,
                  appName: 'App $pkg',
                  settingsRepository: settingsRepo,
                  blockSessionRepository: sessionRepository,
                  nowMsProvider: () => simulatedNowMs,
                  autoOpenModal: false,
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        for (int i = 1; i < packages.length; i++) {
          pkgNotifier.value = packages[i];
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));

          expect(find.text('App ${packages[i]}'), findsOneWidget);
          expect(find.text('05:00'), findsOneWidget);
        }

        for (final pkg in packages) {
          final session = await sessionRepository.getActiveSessionForPackage(
            pkg,
          );
          expect(session, isNotNull);
          expect(session!.packageName, equals(pkg));
          expect(session.status, equals(BlockSession.statusActive));
        }

        simulatedNowMs += 20000;
        pkgNotifier.value = packages[0];
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('App ${packages[0]}'), findsOneWidget);
        expect(find.text('04:40'), findsOneWidget);

        pkgNotifier.value = packages[2];
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('App ${packages[2]}'), findsOneWidget);
        expect(find.text('04:40'), findsOneWidget);
      },
    );

    testWidgets(
      'clock backward manipulation triggers tamper and does not corrupt peer package',
      (tester) async {
        int simulatedNowMs = 1800000000000;
        final logRepo = FakeActivityLogRepository();
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '300'},
        );

        final sessionA = BlockSession(
          packageName: 'com.target.tamper',
          startAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs),
          endAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs + 300000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs),
        );
        final sessionB = BlockSession(
          packageName: 'com.target.victim',
          startAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs),
          endAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs + 300000),
          status: BlockSession.statusActive,
          createdAt: DateTime.fromMillisecondsSinceEpoch(simulatedNowMs),
        );

        await sessionRepository.createSession(sessionA);
        await sessionRepository.createSession(sessionB);

        final pkgNotifier = ValueNotifier<String>('com.target.tamper');

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<String>(
              valueListenable: pkgNotifier,
              builder: (context, pkg, _) {
                return LockedScreen(
                  key: const ValueKey('locked_screen_key'),
                  packageName: pkg,
                  appName: 'Tamper App',
                  settingsRepository: settingsRepo,
                  activityLogRepository: logRepo,
                  blockSessionRepository: sessionRepository,
                  nowMsProvider: () => simulatedNowMs,
                  autoOpenModal: false,
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('05:00'), findsOneWidget);

        simulatedNowMs -= 50000;
        final state = tester.state(find.byType(LockedScreen)) as dynamic;
        state.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();

        expect(find.text('05:00'), findsOneWidget);
        final logs = logRepo.logs
            .where((l) => l.eventType == ActivityLog.eventTamperingDetected)
            .toList();
        expect(logs.isNotEmpty, isTrue);
        expect(logs.first.packageNameSnapshot, equals('com.target.tamper'));

        final victimSession = await sessionRepository
            .getActiveSessionForPackage('com.target.victim');
        expect(victimSession, isNotNull);
        expect(
          victimSession!.startAt.millisecondsSinceEpoch,
          equals(1800000000000),
        );
        expect(
          victimSession.endAt.millisecondsSinceEpoch,
          equals(1800000000000 + 300000),
        );
      },
    );

    testWidgets(
      'forward clock jump triggers anti-tamper penalty on active screen',
      (tester) async {
        int simulatedNowMs = 1850000000000;
        final logRepo = FakeActivityLogRepository();
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '300'},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LockedScreen(
              packageName: 'com.jump.app',
              appName: 'Jump App',
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
              blockSessionRepository: sessionRepository,
              nowMsProvider: () => simulatedNowMs,
              autoOpenModal: false,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('05:00'), findsOneWidget);

        simulatedNowMs += 1000;
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('04:59'), findsOneWidget);

        simulatedNowMs += 20000;
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('05:00'), findsOneWidget);
        final logs = logRepo.logs
            .where((l) => l.eventType == ActivityLog.eventTamperingDetected)
            .toList();
        expect(logs.isNotEmpty, isTrue);
        expect(logs.first.packageNameSnapshot, equals('com.jump.app'));
      },
    );

    testWidgets(
      'widget rebuild with same package preserves ongoing countdown without reset',
      (tester) async {
        int simulatedNowMs = 1900000000000;
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '300'},
        );

        final rebuildNotifier = ValueNotifier<int>(0);

        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<int>(
              valueListenable: rebuildNotifier,
              builder: (context, count, _) {
                return LockedScreen(
                  packageName: 'com.stable.app',
                  appName: 'Stable App',
                  settingsRepository: settingsRepo,
                  blockSessionRepository: sessionRepository,
                  nowMsProvider: () => simulatedNowMs,
                  autoOpenModal: false,
                );
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('05:00'), findsOneWidget);

        simulatedNowMs += 1000;
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('04:59'), findsOneWidget);

        rebuildNotifier.value = 1;
        await tester.pump();

        expect(find.text('04:59'), findsOneWidget);
      },
    );

    testWidgets('resilient fallback when package is null or empty', (
      tester,
    ) async {
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {'waiting_duration_seconds': '120'},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: null,
            appName: null,
            settingsRepository: settingsRepo,
            blockSessionRepository: sessionRepository,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Aplikasi Dibatasi'), findsOneWidget);
      expect(find.text('02:00'), findsOneWidget);
    });

    testWidgets(
      'database session failure fails closed and retries successfully after recovery',
      (tester) async {
        final failingRepo = FailingBlockSessionRepository();
        final settingsRepo = FakeSettingsRepository(
          initialSettings: {'waiting_duration_seconds': '180'},
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LockedScreen(
              packageName: 'com.failure.app',
              appName: 'Failure App',
              settingsRepository: settingsRepo,
              blockSessionRepository: failingRepo,
              autoOpenModal: false,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.textContaining('Gagal memuat sesi pembatasan'),
          findsOneWidget,
        );
        expect(find.text('Coba Lagi'), findsOneWidget);
        expect(find.text('Buka Kunci Aplikasi'), findsNothing);
        expect(find.byType(PasswordUnlockModal), findsNothing);
        expect(failingRepo.sessions, isEmpty);
        expect(failingRepo.loadAttempts, 1);

        await tester.pump(const Duration(seconds: 181));
        expect(find.text('Buka Kunci Aplikasi'), findsNothing);
        expect(find.byType(PasswordUnlockModal), findsNothing);

        failingRepo.fail = false;
        await tester.tap(find.text('Coba Lagi'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Failure App'), findsOneWidget);
        expect(find.text('03:00'), findsOneWidget);
        expect(find.text('Coba Lagi'), findsNothing);
        expect(failingRepo.loadAttempts, 2);
        expect(failingRepo.sessions.single.packageName, 'com.failure.app');
        expect(failingRepo.sessions.single.status, BlockSession.statusActive);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'temporary unlock marks target app session completed while peer app remains active',
      (tester) async {
        final settingsRepo = FakeSettingsRepository(
          expectedPassword: 'correctPass',
        );
        final unlockRepo = FakeTemporaryUnlockRepository();
        final logRepo = FakeActivityLogRepository();
        final appRepo = FakeBlockedAppRepository();
        final channel = FakeBlockingPlatformChannel();
        final now = DateTime.now().millisecondsSinceEpoch;

        await sessionRepository.createSession(
          BlockSession(
            packageName: 'com.app.to_unlock',
            startAt: DateTime.fromMillisecondsSinceEpoch(now - 10000),
            endAt: DateTime.fromMillisecondsSinceEpoch(now + 290000),
            status: BlockSession.statusActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(now - 10000),
          ),
        );
        await sessionRepository.createSession(
          BlockSession(
            packageName: 'com.app.stay_locked',
            startAt: DateTime.fromMillisecondsSinceEpoch(now - 10000),
            endAt: DateTime.fromMillisecondsSinceEpoch(now + 290000),
            status: BlockSession.statusActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(now - 10000),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: LockedScreen(
              packageName: 'com.app.to_unlock',
              appName: 'Unlock Me App',
              appId: 10,
              startAtEpochMs: now - 10000,
              endAtEpochMs: now - 1000,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
              blockedAppRepository: appRepo,
              platformChannel: channel,
              blockSessionRepository: sessionRepository,
              autoOpenModal: true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(PasswordUnlockModal), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'correctPass');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Buka Sementara'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          await sessionRepository.getActiveSessionForPackage(
            'com.app.to_unlock',
          ),
          isNull,
        );

        final peerSession = await sessionRepository.getActiveSessionForPackage(
          'com.app.stay_locked',
        );
        expect(peerSession, isNotNull);
        expect(peerSession!.status, equals(BlockSession.statusActive));
      },
    );
  });
}

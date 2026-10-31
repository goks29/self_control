import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/repositories/block_session_repository.dart';
import 'package:self_control/data/repositories/block_session_repository_impl.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  late AppDatabase appDatabase;
  late Database db;
  late BlockSessionRepository sessionRepository;

  setUp(() async {
    appDatabase = AppDatabase.instance;
    db = await appDatabase.initDatabase(
      customPath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    sessionRepository = BlockSessionRepositoryImpl(db: db);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('M2 Adversarial Rapid Lock Switching & Concurrency Stress Tests', () {
    test('rapid sequential lock sessions across 5 apps maintain zero timer collisions', () async {
      final baseEpoch = 1500000000;
      final packages = [
        'com.social.insta',
        'com.video.tok',
        'com.stream.tube',
        'com.chat.tele',
        'com.game.gacha',
      ];

      for (int i = 0; i < packages.length; i++) {
        final pkg = packages[i];
        final startAt = DateTime.fromMillisecondsSinceEpoch(baseEpoch + (i * 10000));
        final endAt = startAt.add(Duration(seconds: 300 + (i * 60)));
        final session = BlockSession(
          packageName: pkg,
          startAt: startAt,
          endAt: endAt,
          status: BlockSession.statusActive,
          createdAt: startAt,
        );
        await sessionRepository.createSession(session);
      }

      for (int i = 0; i < packages.length; i++) {
        final pkg = packages[i];
        final session = await sessionRepository.getActiveSessionForPackage(pkg);
        expect(session, isNotNull);
        expect(session!.packageName, equals(pkg));
        expect(session.startAt.millisecondsSinceEpoch, equals(baseEpoch + (i * 10000)));
        expect(session.endAt.difference(session.startAt).inSeconds, equals(300 + (i * 60)));
      }

      await sessionRepository.completeActiveSessionsForPackage('com.video.tok');
      expect(await sessionRepository.getActiveSessionForPackage('com.video.tok'), isNull);

      for (final pkg in packages.where((p) => p != 'com.video.tok')) {
        final active = await sessionRepository.getActiveSessionForPackage(pkg);
        expect(active, isNotNull);
        expect(active!.status, equals(BlockSession.statusActive));
      }
    });

    test('high concurrency asynchronous operations complete without race conditions or deadlocks', () async {
      final baseEpoch = 2500000000;
      final packages = List.generate(10, (i) => 'com.concurrent.app$i');

      final futures = <Future<dynamic>>[];
      for (int i = 0; i < packages.length; i++) {
        final pkg = packages[i];
        futures.add(
          sessionRepository.createSession(
            BlockSession(
              packageName: pkg,
              startAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch),
              endAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch + 300000),
              status: BlockSession.statusActive,
              createdAt: DateTime.fromMillisecondsSinceEpoch(baseEpoch),
            ),
          ),
        );
      }
      await Future.wait(futures);

      final queryFutures = packages.map((pkg) => sessionRepository.getActiveSessionForPackage(pkg)).toList();
      final results = await Future.wait(queryFutures);
      for (int i = 0; i < packages.length; i++) {
        expect(results[i], isNotNull);
        expect(results[i]!.packageName, equals(packages[i]));
      }

      final completeFutures = packages.take(5).map((pkg) => sessionRepository.completeActiveSessionsForPackage(pkg)).toList();
      await Future.wait(completeFutures);

      for (int i = 0; i < 5; i++) {
        expect(await sessionRepository.getActiveSessionForPackage(packages[i]), isNull);
      }
      for (int i = 5; i < 10; i++) {
        expect(await sessionRepository.getActiveSessionForPackage(packages[i]), isNotNull);
      }
    });

    testWidgets('backward tamper detection on one app does not reset or corrupt peer app session', (tester) async {
      int fakeNow = 3000000000;
      final logRepo = FakeActivityLogRepository();
      final widgetSessionRepo = FakeBlockSessionRepository();
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {'waiting_duration_seconds': '300'},
      );

      final sessionA = BlockSession(
        packageName: 'com.tamper.app',
        startAt: DateTime.fromMillisecondsSinceEpoch(fakeNow),
        endAt: DateTime.fromMillisecondsSinceEpoch(fakeNow + 300000),
        status: BlockSession.statusActive,
        createdAt: DateTime.fromMillisecondsSinceEpoch(fakeNow),
      );
      final sessionB = BlockSession(
        packageName: 'com.innocent.app',
        startAt: DateTime.fromMillisecondsSinceEpoch(fakeNow),
        endAt: DateTime.fromMillisecondsSinceEpoch(fakeNow + 300000),
        status: BlockSession.statusActive,
        createdAt: DateTime.fromMillisecondsSinceEpoch(fakeNow),
      );
      await widgetSessionRepo.createSession(sessionA);
      final idB = await widgetSessionRepo.createSession(sessionB);

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.tamper.app',
            appName: 'Tamper App',
            settingsRepository: settingsRepo,
            activityLogRepository: logRepo,
            blockSessionRepository: widgetSessionRepo,
            nowMsProvider: () => fakeNow,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('05:00'), findsOneWidget);

      fakeNow = 2500000000;
      final state = tester.state(find.byType(LockedScreen)) as dynamic;
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      final tamperLogs = logRepo.logs.where((l) => l.eventType == ActivityLog.eventTamperingDetected).toList();
      expect(tamperLogs.isNotEmpty, isTrue);
      expect(tamperLogs.first.packageNameSnapshot, equals('com.tamper.app'));

      final innocentSession = await widgetSessionRepo.getActiveSessionForPackage('com.innocent.app');
      expect(innocentSession, isNotNull);
      expect(innocentSession!.id, equals(idB));
      expect(innocentSession.startAt.millisecondsSinceEpoch, equals(3000000000));
      expect(innocentSession.endAt.millisecondsSinceEpoch, equals(3000000000 + 300000));
    });
  });
}

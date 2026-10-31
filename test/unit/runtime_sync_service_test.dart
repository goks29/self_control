import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/blocking_operation_queue.dart';
import 'package:self_control/application/services/runtime_sync_service.dart';
import 'package:self_control/application/services/temporary_unlock_service.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/data/repositories/temporary_unlock_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../presentation/test_helpers.dart';

void main() {
  group('RuntimeSyncService', () {
    test(
      'concurrent synchronization shares one flight and imports once',
      () async {
        final gate = Completer<void>();
        final channel = _ControlledChannel()..bootGate = gate.future;
        channel.pendingBootEvents.add(1000);
        channel.pendingActivityLogs.add({
          'packageName': 'com.example.app',
          'timestampMs': 2000,
        });
        final logs = FakeActivityLogRepository();
        final unlocks = _OneShotExpiryRepository();
        final service = RuntimeSyncService(
          channel: channel,
          logs: logs,
          apps: FakeBlockedAppRepository(),
          unlocks: unlocks,
        );

        final first = service.synchronize();
        final second = service.synchronize();
        expect(identical(first, second), isTrue);
        expect(channel.bootConsumptions, 1);
        expect(logs.logs, isEmpty);
        gate.complete();
        await Future.wait([first, second]);

        expect(channel.bootConsumptions, 1);
        expect(channel.activityConsumptions, 1);
        expect(unlocks.expiryCalls, 1);
        expect(logs.logs.map((log) => log.eventType), [
          ActivityLog.eventBootCompletedSync,
          ActivityLog.eventBlockedAttempt,
        ]);
        await service.synchronize();
        expect(channel.bootConsumptions, 2);
        expect(logs.logs, hasLength(2));
      },
    );

    for (final bootEvent in [true, false]) {
      test('retains failed ${bootEvent ? 'boot' : 'activity'} log and retries '
          'without duplicating successful imports', () async {
        final channel = _ControlledChannel();
        void enqueue(int timestamp) {
          if (bootEvent) {
            channel.pendingBootEvents.add(timestamp);
          } else {
            channel.pendingActivityLogs.add({
              'packageName': 'com.example.app',
              'timestampMs': timestamp,
            });
          }
        }

        for (final timestamp in [1000, 2000, 3000]) {
          enqueue(timestamp);
        }
        final logs = _FailOnceLogRepository(failAtMs: 2000);
        final service = RuntimeSyncService(
          channel: channel,
          logs: logs,
          apps: FakeBlockedAppRepository(),
          unlocks: FakeTemporaryUnlockRepository(),
        );

        await expectLater(service.synchronize(), throwsStateError);
        expect(channel.pendingBootEvents, isEmpty);
        expect(channel.pendingActivityLogs, isEmpty);
        expect(logs.logs.map((log) => log.attemptedAt.millisecondsSinceEpoch), [
          1000,
        ]);

        enqueue(4000);
        await service.synchronize();
        await service.synchronize();

        expect(logs.attempts, [1000, 2000, 2000, 3000, 4000]);
        expect(logs.logs.map((log) => log.attemptedAt.millisecondsSinceEpoch), [
          1000,
          2000,
          3000,
          4000,
        ]);
      });
    }

    test(
      'retains an unconfirmed revocation even when expiry reports it once',
      () async {
        final channel = _ControlledChannel()..confirmRevocation = false;
        final unlocks = _OneShotExpiryRepository()
          ..expiredPackages.add('com.example.expired');
        final service = RuntimeSyncService(
          channel: channel,
          logs: FakeActivityLogRepository(),
          apps: FakeBlockedAppRepository(),
          unlocks: unlocks,
        );

        await expectLater(service.synchronize(), throwsStateError);
        expect(unlocks.expiredPackages, isEmpty);
        expect(channel.revocations, ['com.example.expired']);

        channel.confirmRevocation = true;
        await service.synchronize();
        await service.synchronize();

        expect(unlocks.expiryCalls, 3);
        expect(channel.revocations, [
          'com.example.expired',
          'com.example.expired',
        ]);
      },
    );

    test(
      'invalid native timestamps fall back to the synchronization time',
      () async {
        final channel = _ControlledChannel();
        final invalidActivityTimestamps = <Object?>[
          null,
          'not a timestamp',
          true,
          -1,
          double.nan,
          double.infinity,
          double.negativeInfinity,
          8640000000000001,
        ];
        channel.pendingBootEvents.addAll([-1, 8640000000000001]);
        for (final timestamp in invalidActivityTimestamps) {
          channel.pendingActivityLogs.add({
            'packageName': 'com.example.app',
            'timestampMs': timestamp,
          });
        }
        final logs = FakeActivityLogRepository();
        final service = RuntimeSyncService(
          channel: channel,
          logs: logs,
          apps: FakeBlockedAppRepository(),
          unlocks: FakeTemporaryUnlockRepository(),
        );
        final before = DateTime.now().millisecondsSinceEpoch;

        await service.synchronize();

        final after = DateTime.now().millisecondsSinceEpoch;
        expect(logs.logs, hasLength(invalidActivityTimestamps.length + 2));
        for (final log in logs.logs) {
          expect(
            log.attemptedAt.millisecondsSinceEpoch,
            inInclusiveRange(before, after),
          );
        }
      },
    );
  });

  test('BlockingOperationQueue runs in order and survives failures', () async {
    final queue = BlockingOperationQueue();
    final events = <String>[];
    final release = Completer<void>();
    final first = queue.run(() async {
      events.add('first:start');
      await release.future;
      events.add('first:end');
      return 1;
    });
    final failed = queue.run<int>(() {
      events.add('failed');
      throw StateError('operation failed');
    });
    final failedExpectation = expectLater(failed, throwsStateError);
    final third = queue.run(() {
      events.add('third');
      return 3;
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['first:start']);
    release.complete();

    expect(await first, 1);
    await failedExpectation;
    expect(await third, 3);
    expect(events, ['first:start', 'first:end', 'failed', 'third']);
  });

  group('grant and expiry serialization', () {
    late _ControlledChannel channel;
    late _OneShotExpiryRepository unlocks;
    late _ControlledSettings settings;
    late FakeActivityLogRepository logs;
    late RuntimeSyncService runtime;
    late TemporaryUnlockService grants;

    setUp(() {
      channel = _ControlledChannel();
      unlocks = _OneShotExpiryRepository()
        ..expiredPackages.add('com.example.expired');
      settings = _ControlledSettings();
      logs = FakeActivityLogRepository();
      runtime = RuntimeSyncService(
        channel: channel,
        logs: logs,
        apps: FakeBlockedAppRepository(),
        unlocks: unlocks,
      );
      grants = TemporaryUnlockService(
        settingsRepository: settings,
        unlockRepository: unlocks,
        appRepository: FakeBlockedAppRepository(),
        logRepository: logs,
        platformChannel: channel,
      );
    });

    Future<String?> grant({bool Function()? isCancelled}) => grants.unlock(
      password: 'secret',
      packageName: 'com.example.expired',
      appName: 'Example',
      appId: 7,
      durationSeconds: 300,
      isCancelled: isCancelled,
    );

    test('discards failed revocation when a newer grant is active', () async {
      channel.confirmRevocation = false;
      await expectLater(runtime.synchronize(), throwsStateError);
      expect(unlocks.expiredPackages, isEmpty);

      expect(await grant(), isNull);
      channel.confirmRevocation = true;
      await runtime.synchronize();
      expect(channel.revocations, ['com.example.expired']);
      expect(channel.nativeUnlocked, isTrue);

      // The stale retry must be discarded, not merely skipped for this run.
      unlocks.unlocks.clear();
      await runtime.synchronize();
      expect(channel.revocations, ['com.example.expired']);
    });

    test('active lookup and revoke cannot interleave with a new grant', () async {
      final lookupEntered = Completer<void>();
      final finishLookup = Completer<TemporaryUnlock?>();
      unlocks.onLookup = () {
        lookupEntered.complete();
        return finishLookup.future;
      };
      final sync = runtime.synchronize();
      // Allow the pre-fix service (which never checks active grants) to finish.
      await Future<void>.delayed(Duration.zero);
      expect(lookupEntered.isCompleted, isTrue);
      final newGrant = grant();
      await Future<void>.delayed(Duration.zero);
      expect(settings.verifications, 0);
      expect(unlocks.unlocks, isEmpty);
      finishLookup.complete(null);
      await Future.wait<Object?>([sync, newGrant]);

      expect(channel.nativeOperations, ['revoke', 'grant']);
      expect(channel.nativeUnlocked, isTrue);
    });

    test(
      'expiry waits for the entire grant starting at password verification',
      () async {
        final finishPassword = Completer<void>();
        settings.passwordGate = finishPassword.future;
        final newGrant = grant();
        await Future<void>.delayed(Duration.zero);
        expect(settings.verifications, 1);
        final sync = runtime.synchronize();
        await Future<void>.delayed(Duration.zero);
        expect(unlocks.expiryCalls, 0);
        finishPassword.complete();
        await Future.wait<Object?>([newGrant, sync]);

        expect(channel.nativeOperations, ['grant']);
        expect(channel.nativeUnlocked, isTrue);
      },
    );

    test('native revocation completion holds the gate and queued cancellation survives', () async {
      final revokeEntered = Completer<void>();
      final finishRevoke = Completer<void>();
      channel.onRevoke = () async {
        revokeEntered.complete();
        await finishRevoke.future;
      };
      final sync = runtime.synchronize();
      await revokeEntered.future;
      var cancelled = false;
      final newGrant = grant(isCancelled: () => cancelled);
      final rejected = expectLater(
        newGrant,
        throwsA(isA<TemporaryUnlockException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(settings.verifications, 0);
      cancelled = true;
      finishRevoke.complete();
      await sync;
      await rejected;
      expect(unlocks.unlocks, isEmpty);
      expect(channel.nativeOperations, ['revoke']);
      // Neither cancellation nor the preceding queued operation poisons grants.
      expect(await grant(), isNull);
    });

    test(
      'lookup errors retain retries and do not poison subsequent grants',
      () async {
        unlocks.onLookup = () async => throw StateError('lookup failed');
        await expectLater(runtime.synchronize(), throwsStateError);
        expect(channel.revocations, isEmpty);
        expect(await grant(), isNull);

        unlocks.onLookup = null;
        await runtime.synchronize();
        expect(unlocks.expiredPackages, isEmpty);
        expect(channel.revocations, isEmpty);
        expect(channel.nativeUnlocked, isTrue);
      },
    );

    test('log import does not hold up grants', () async {
      final finishImport = Completer<void>();
      channel.bootGate = finishImport.future;
      final sync = runtime.synchronize();
      expect(await grant(), isNull);
      expect(channel.nativeUnlocked, isTrue);
      finishImport.complete();
      await sync;
      expect(channel.revocations, isEmpty);
    });
  });

  group('RuntimeSyncService with FFI unlock repository', () {
    late AppDatabase appDatabase;
    late Database db;
    late _ControlledChannel channel;
    late RuntimeSyncService service;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      appDatabase = AppDatabase();
      db = await appDatabase.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      channel = _ControlledChannel();
      service = RuntimeSyncService(
        channel: channel,
        logs: FakeActivityLogRepository(),
        apps: FakeBlockedAppRepository(),
        unlocks: TemporaryUnlockRepositoryImpl(db: db),
      );
    });
    tearDown(() => appDatabase.close());

    test(
      'surfaces expiry query errors and allows a later synchronization',
      () async {
        await db.execute(
          'ALTER TABLE temporary_unlocks RENAME TO unavailable_unlocks',
        );

        await expectLater(
          service.synchronize(),
          throwsA(isA<DatabaseException>()),
        );
        expect(channel.revocations, isEmpty);

        await db.execute(
          'ALTER TABLE unavailable_unlocks RENAME TO temporary_unlocks',
        );
        await service.synchronize();
        expect(channel.bootConsumptions, 2);
      },
    );

    test(
      'surfaces expiry transaction errors and retries the rolled back expiry',
      () async {
        final now = DateTime.now().millisecondsSinceEpoch;
        final appId = await db.insert(AppDatabase.tableBlockedApps, {
          'package_name': 'com.example.expired',
          'app_name': 'Expired app',
          'created_at': now,
        });
        await db.insert(AppDatabase.tableTemporaryUnlocks, {
          'app_id': appId,
          'start_at': now - 120000,
          'end_at': now - 60000,
          'status': TemporaryUnlock.statusActive,
          'created_at': now - 120000,
        });
        await db.execute('''
        CREATE TRIGGER reject_expiry_log BEFORE INSERT ON activity_logs
        BEGIN SELECT RAISE(ABORT, 'expiry log write failed'); END
      ''');

        await expectLater(
          service.synchronize(),
          throwsA(isA<DatabaseException>()),
        );
        expect(channel.revocations, isEmpty);
        expect(
          (await db.query(AppDatabase.tableTemporaryUnlocks)).single['status'],
          TemporaryUnlock.statusActive,
        );
        expect(await db.query(AppDatabase.tableActivityLogs), isEmpty);

        await db.execute('DROP TRIGGER reject_expiry_log');
        await service.synchronize();
        await service.synchronize();

        expect(channel.revocations, ['com.example.expired']);
        expect(
          (await db.query(AppDatabase.tableTemporaryUnlocks)).single['status'],
          TemporaryUnlock.statusExpired,
        );
        final logs = await db.query(AppDatabase.tableActivityLogs);
        expect(logs, hasLength(1));
        expect(
          logs.single['event_type'],
          ActivityLog.eventTemporaryUnlockExpired,
        );
      },
    );
  });
}

class _ControlledChannel extends FakeBlockingPlatformChannel {
  Future<void>? bootGate;
  int bootConsumptions = 0;
  int activityConsumptions = 0;
  bool confirmRevocation = true;
  final revocations = <String>[];
  final nativeOperations = <String>[];
  bool nativeUnlocked = false;
  Future<void> Function()? onRevoke;

  @override
  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async {
    nativeOperations.add('grant');
    nativeUnlocked = true;
    return true;
  }

  @override
  Future<List<int>> consumePendingBootEvents() async {
    bootConsumptions++;
    if (bootGate != null) await bootGate;
    return super.consumePendingBootEvents();
  }

  @override
  Future<List<Map<String, dynamic>>> consumePendingActivityLogs() {
    activityConsumptions++;
    return super.consumePendingActivityLogs();
  }

  @override
  Future<bool> revokeTemporaryUnlock(String packageName) async {
    revocations.add(packageName);
    await onRevoke?.call();
    nativeOperations.add('revoke');
    if (confirmRevocation) nativeUnlocked = false;
    return confirmRevocation;
  }
}

class _FailOnceLogRepository extends FakeActivityLogRepository {
  _FailOnceLogRepository({required this.failAtMs});

  final int failAtMs;
  bool failed = false;
  final attempts = <int>[];

  @override
  Future<void> logEvent(ActivityLog log) async {
    final timestamp = log.attemptedAt.millisecondsSinceEpoch;
    attempts.add(timestamp);
    if (!failed && timestamp == failAtMs) {
      failed = true;
      throw StateError('log write failed');
    }
    await super.logEvent(log);
  }
}

class _ControlledSettings extends FakeSettingsRepository {
  _ControlledSettings() : super(expectedPassword: 'secret');

  Future<void>? passwordGate;
  int verifications = 0;

  @override
  Future<bool> verifyPassword(String plainPassword) async {
    verifications++;
    await passwordGate;
    return super.verifyPassword(plainPassword);
  }
}

class _OneShotExpiryRepository extends FakeTemporaryUnlockRepository {
  final expiredPackages = <String>[];
  int expiryCalls = 0;
  Future<TemporaryUnlock?> Function()? onLookup;

  @override
  Future<TemporaryUnlock?> getActiveUnlockForPackage(String packageName) async {
    if (onLookup != null) return onLookup!();
    if (packageName != 'com.example.expired') return null;
    for (final unlock in unlocks.reversed) {
      if (unlock.isActive && unlock.endAt.isAfter(DateTime.now())) {
        return unlock;
      }
    }
    return null;
  }

  @override
  Future<List<String>> expireOutdatedUnlocks() async {
    expiryCalls++;
    final expired = List<String>.of(expiredPackages);
    expiredPackages.clear();
    return expired;
  }
}

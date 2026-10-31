import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/temporary_unlock_service.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/temporary_unlock.dart';

import '../presentation/test_helpers.dart';

class _Native extends FakeBlockingPlatformChannel {
  bool success = true;
  bool throwOnGrant = false;
  bool revokeSuccess = true;
  int grants = 0;
  int revokes = 0;
  Future<bool> Function()? onGrant;

  @override
  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async {
    grants++;
    if (throwOnGrant) throw StateError('native disconnected');
    return onGrant != null ? await onGrant!() : success;
  }

  @override
  Future<bool> revokeTemporaryUnlock(String packageName) async {
    revokes++;
    return revokeSuccess;
  }
}

class _Unlocks extends FakeTemporaryUnlockRepository {
  bool failCreate = false;
  bool failRevoke = false;

  @override
  Future<int> createUnlock(TemporaryUnlock unlock) async {
    if (failCreate) throw StateError('storage');
    return super.createUnlock(unlock);
  }

  @override
  Future<void> updateUnlockStatus(int id, String status) async {
    if (failRevoke) throw StateError('storage');
    await super.updateUnlockStatus(id, status);
  }
}

class _Sessions extends FakeBlockSessionRepository {
  int completions = 0;
  bool fail = false;

  @override
  Future<void> completeActiveSessionsForPackage(String packageName) async {
    if (fail) throw StateError('session write failed');
    completions++;
  }
}

class _Logs extends FakeActivityLogRepository {
  bool fail = false;

  @override
  Future<void> logEvent(ActivityLog log) async {
    if (fail) throw StateError('audit unavailable');
    await super.logEvent(log);
  }
}

void main() {
  late _Native native;
  late _Unlocks unlocks;
  late _Sessions sessions;
  late _Logs logs;
  late FakeBlockedAppRepository apps;
  late TemporaryUnlockService service;

  setUp(() {
    native = _Native();
    unlocks = _Unlocks();
    sessions = _Sessions();
    logs = _Logs();
    apps = FakeBlockedAppRepository();
    service = TemporaryUnlockService(
      settingsRepository: FakeSettingsRepository(expectedPassword: 'secret'),
      unlockRepository: unlocks,
      appRepository: apps,
      logRepository: logs,
      platformChannel: native,
      sessionRepository: sessions,
    );
  });

  Future<String?> grant({
    int? appId = 7,
    String? package = 'com.test',
    bool Function()? isCancelled,
  }) => service.unlock(
    password: 'secret',
    packageName: package,
    appName: 'Test',
    appId: appId,
    durationSeconds: 300,
    isCancelled: isCancelled,
  );

  test('success persists a valid id and completes sessions only after native confirmation', () async {
    final confirmation = Completer<bool>();
    native.onGrant = () => confirmation.future;
    final future = grant();
    await Future<void>.delayed(Duration.zero);
    expect(unlocks.unlocks.single.appId, 7);
    expect(sessions.completions, 0);
    expect(logs.logs, isEmpty);
    confirmation.complete(true);
    expect(await future, isNull);
    expect(unlocks.unlocks.single.isActive, isTrue);
    expect(sessions.completions, 1);
    expect(logs.logs.single.eventType, ActivityLog.eventTemporaryUnlockStarted);
  });

  for (final throwing in [false, true]) {
    test(
      'native ${throwing ? 'exception' : 'rejection'} rolls back without success effects',
      () async {
        native.success = false;
        native.throwOnGrant = throwing;
        await expectLater(grant(), throwsA(isA<TemporaryUnlockException>()));
        expect(unlocks.unlocks.single.isRevoked, isTrue);
        expect(native.revokes, 1);
        expect(sessions.completions, 0);
        expect(logs.logs, isEmpty);
      },
    );
  }

  test('missing app id is resolved by package before persisting', () async {
    apps.apps.add(
      BlockedApp(
        id: 22,
        packageName: 'com.test',
        appName: 'Test',
        createdAt: DateTime(2026),
      ),
    );
    await grant(appId: 0);
    expect(unlocks.unlocks.single.appId, 22);
  });

  test(
    'unknown app never creates a synthetic persisted or native grant',
    () async {
      await expectLater(
        grant(appId: null),
        throwsA(isA<TemporaryUnlockException>()),
      );
      expect(unlocks.unlocks, isEmpty);
      expect(native.grants, 0);
    },
  );

  test('missing package cannot grant access even with an app id', () async {
    await expectLater(
      grant(package: null),
      throwsA(isA<TemporaryUnlockException>()),
    );
    expect(unlocks.unlocks, isEmpty);
    expect(native.grants, 0);
  });

  test('persistence failure does not create native access', () async {
    unlocks.failCreate = true;
    await expectLater(grant(), throwsA(isA<TemporaryUnlockException>()));
    expect(native.grants, 0);
    expect(sessions.completions, 0);
    expect(logs.logs, isEmpty);
  });

  test('database rollback failure still attempts native revocation and surfaces uncertainty', () async {
    native.success = false;
    unlocks.failRevoke = true;
    await expectLater(
      grant(),
      throwsA(
        isA<TemporaryUnlockException>().having(
          (e) => e.message,
          'message',
          contains('belum terkonfirmasi'),
        ),
      ),
    );
    expect(native.revokes, 1);
    expect(sessions.completions, 0);
  });

  test('native revocation failure is explicitly reported', () async {
    native.success = false;
    native.revokeSuccess = false;
    await expectLater(
      grant(),
      throwsA(
        isA<TemporaryUnlockException>().having(
          (e) => e.message,
          'message',
          contains('belum terkonfirmasi'),
        ),
      ),
    );
    expect(unlocks.unlocks.single.isRevoked, isTrue);
  });

  test(
    'session persistence failure revokes the confirmed native grant',
    () async {
      sessions.fail = true;
      await expectLater(grant(), throwsA(isA<TemporaryUnlockException>()));
      expect(unlocks.unlocks.single.isRevoked, isTrue);
      expect(native.revokes, 1);
      expect(logs.logs, isEmpty);
    },
  );

  test(
    'disposal during native sync compensates instead of completing sessions',
    () async {
      var cancelled = false;
      native.onGrant = () async {
        cancelled = true;
        return true;
      };
      await expectLater(
        grant(isCancelled: () => cancelled),
        throwsA(isA<TemporaryUnlockException>()),
      );
      expect(unlocks.unlocks.single.isRevoked, isTrue);
      expect(native.revokes, 1);
      expect(sessions.completions, 0);
    },
  );

  test('failed password audit cannot mask rejection or grant access', () async {
    logs.fail = true;
    await expectLater(
      service.unlock(
        password: 'incorrect-password',
        packageName: 'com.test',
        appName: 'Test',
        appId: 7,
        durationSeconds: 300,
      ),
      throwsA(
        isA<TemporaryUnlockException>().having(
          (error) => error.message,
          'message',
          'Password salah. Silakan coba lagi.',
        ),
      ),
    );
    expect(native.grants, 0);
    expect(unlocks.unlocks, isEmpty);
    expect(sessions.completions, 0);
  });

  test(
    'audit failure reports a warning without undoing a committed grant',
    () async {
      logs.fail = true;
      expect(await grant(), contains('riwayat'));
      expect(unlocks.unlocks.single.isActive, isTrue);
      expect(native.revokes, 0);
      expect(sessions.completions, 1);
    },
  );
}

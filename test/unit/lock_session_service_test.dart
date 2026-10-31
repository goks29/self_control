import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/lock_session_service.dart';
import 'package:self_control/data/models/block_session.dart';

import '../presentation/test_helpers.dart';

void main() {
  test('setup reuses only the requested package session', () async {
    final sessions = FakeBlockSessionRepository([
      BlockSession(
        packageName: 'com.a',
        startAt: DateTime.fromMillisecondsSinceEpoch(100000),
        endAt: DateTime.fromMillisecondsSinceEpoch(400000),
        status: BlockSession.statusActive,
        createdAt: DateTime.fromMillisecondsSinceEpoch(100000),
      ),
    ]);
    final service = LockSessionService(
      settingsRepository: FakeSettingsRepository(),
      appRepository: FakeBlockedAppRepository(),
      sessionRepository: sessions,
    );
    final a = await service.initialize(
      packageName: 'com.a',
      nowMs: () => 200000,
    );
    final b = await service.initialize(
      packageName: 'com.b',
      nowMs: () => 200000,
    );
    expect(a.startEpochMs, 100000);
    expect(a.endEpochMs, 400000);
    expect(b.startEpochMs, 200000);
    expect(b.endEpochMs, 500000);
    expect(sessions.sessions.length, 2);
  });

  test('countdown retains ceiling and exact backward tolerance', () {
    final policy = LockCountdownPolicy(
      startEpochMs: 100000,
      endEpochMs: 400001,
      openedAtMs: 100000,
    );
    expect(
      policy.tick(nowMs: 100002, monotonicElapsedMs: 2).remainingSeconds,
      300,
    );
    expect(
      policy.tick(nowMs: 97002, monotonicElapsedMs: 3).tamperingDetected,
      isFalse,
    );
    final reset = policy.tick(nowMs: 94001, monotonicElapsedMs: 4);
    expect(reset.tamperingDetected, isTrue);
    expect(reset.remainingSeconds, 301);
    expect(policy.endEpochMs, 395001);
  });

  test(
    'forward jumps reset the full duration but normal elapsed time expires',
    () {
      final policy = LockCountdownPolicy(
        startEpochMs: 100000,
        endEpochMs: 400000,
        openedAtMs: 100000,
      );
      final jump = policy.tick(nowMs: 500000, monotonicElapsedMs: 1000);
      expect(jump.tamperingDetected, isTrue);
      expect(jump.remainingSeconds, 300);
      expect(
        policy.tick(nowMs: 800000, monotonicElapsedMs: 300000).remainingSeconds,
        0,
      );
    },
  );

  test('nearly completed monotonic wait does not cause a forward reset', () {
    final policy = LockCountdownPolicy(
      startEpochMs: 100000,
      endEpochMs: 400000,
      openedAtMs: 100000,
    );
    expect(
      policy.tick(nowMs: 500000, monotonicElapsedMs: 298000).tamperingDetected,
      isFalse,
    );
  });
}

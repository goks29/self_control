import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/runtime_sync_service.dart';
import 'package:self_control/data/models/activity_log.dart';

import '../presentation/test_helpers.dart';

class _FailingLogs extends FakeActivityLogRepository {
  bool fail = true;
  @override
  Future<void> logEvent(ActivityLog log) async {
    if (fail) throw StateError('database busy');
    await super.logEvent(log);
  }
}

void main() {
  RuntimeSyncService service(
    FakeBlockingPlatformChannel channel,
    FakeActivityLogRepository logs,
  ) => RuntimeSyncService(
    channel: channel,
    logs: logs,
    apps: FakeBlockedAppRepository(),
    unlocks: FakeTemporaryUnlockRepository(),
  );

  test('successful reset discards retained pre-reset imports', () async {
    final channel = FakeBlockingPlatformChannel()..pendingBootEvents = [1000];
    final logs = _FailingLogs();
    final sync = service(channel, logs);

    await expectLater(sync.synchronize(), throwsStateError);
    await sync.runExclusiveReset(() async {});
    logs.fail = false;
    await sync.synchronize();

    expect(logs.logs, isEmpty);
  });

  test('failed reset keeps retained imports for retry', () async {
    final channel = FakeBlockingPlatformChannel()..pendingBootEvents = [1000];
    final logs = _FailingLogs();
    final sync = service(channel, logs);

    await expectLater(sync.synchronize(), throwsStateError);
    await expectLater(
      sync.runExclusiveReset(() async => throw StateError('reset failed')),
      throwsStateError,
    );
    logs.fail = false;
    await sync.synchronize();

    expect(logs.logs, hasLength(1));
  });

  test('reset waits for in-flight sync and blocks sync during reset', () async {
    final gate = Completer<void>();
    final channel = _GatedChannel(gate.future)..pendingBootEvents = [1000];
    final logs = FakeActivityLogRepository();
    final sync = service(channel, logs);
    final events = <String>[];

    final flight = sync.synchronize().then((_) => events.add('sync'));
    final reset = sync.runExclusiveReset(() async {
      events.add('reset-start');
      await sync.synchronize();
      channel.pendingBootEvents = [2000];
      events.add('reset-end');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);

    gate.complete();
    await Future.wait([flight, reset]);
    await sync.synchronize();

    expect(events, ['sync', 'reset-start', 'reset-end']);
    expect(logs.logs.map((l) => l.attemptedAt.millisecondsSinceEpoch), [
      1000,
      2000,
    ]);
  });
}

class _GatedChannel extends FakeBlockingPlatformChannel {
  _GatedChannel(this.gate);
  final Future<void> gate;

  @override
  Future<List<int>> consumePendingBootEvents() async {
    await gate;
    return super.consumePendingBootEvents();
  }
}

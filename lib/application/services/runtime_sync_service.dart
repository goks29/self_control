import '../../core/platform/blocking_platform_channel.dart';
import '../../data/models/activity_log.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/temporary_unlock_repository.dart';
import 'blocking_operation_queue.dart';

/// Serializes native imports and retains failed writes/revocations for retry
/// during this application session. Native consumption is not an acknowledgement
/// protocol, so these queues cannot guarantee delivery after process death.
class RuntimeSyncService {
  RuntimeSyncService({
    required this.channel,
    required this.logs,
    required this.apps,
    required this.unlocks,
    BlockingOperationQueue? operationQueue,
  }) : _operations = operationQueue ?? BlockingOperationQueue.shared;

  final BlockingPlatformChannel channel;
  final ActivityLogRepository logs;
  final BlockedAppRepository apps;
  final TemporaryUnlockRepository unlocks;
  final BlockingOperationQueue _operations;
  final List<int> _bootEvents = [];
  final List<Map<String, dynamic>> _activityLogs = [];
  final Set<String> _revocations = {};
  Future<void>? _inFlight;
  bool _resetting = false;

  /// Skips (without error) while a reset is running; callers resynchronize
  /// after the reset completes.
  Future<void> synchronize() {
    if (_resetting) return Future.value();
    return _inFlight ??= _synchronize().whenComplete(() => _inFlight = null);
  }

  /// Runs a destructive reset with no synchronization in progress. Retained
  /// retries describe pre-reset data, so they are discarded only if it succeeds.
  Future<T> runExclusiveReset<T>(Future<T> Function() reset) async {
    _resetting = true;
    try {
      try {
        await _inFlight;
      } catch (_) {
        // The in-flight failure was already reported to its caller.
      }
      final result = await reset();
      _bootEvents.clear();
      _activityLogs.clear();
      _revocations.clear();
      return result;
    } finally {
      _resetting = false;
    }
  }

  Future<void> _synchronize() async {
    _bootEvents.addAll(await channel.consumePendingBootEvents());
    while (_bootEvents.isNotEmpty) {
      await logs.logEvent(
        ActivityLog(
          packageNameSnapshot: 'system',
          appNameSnapshot: 'BootReceiver',
          eventType: ActivityLog.eventBootCompletedSync,
          attemptedAt: _safeDate(_bootEvents.first),
        ),
      );
      _bootEvents.removeAt(0);
    }

    _activityLogs.addAll(await channel.consumePendingActivityLogs());
    while (_activityLogs.isNotEmpty) {
      final raw = _activityLogs.first;
      final package = raw['packageName'] is String
          ? raw['packageName'] as String
          : '';
      final app = package.isEmpty
          ? null
          : await apps.getAppByPackageName(package);
      await logs.logEvent(
        ActivityLog(
          appId: app?.id,
          packageNameSnapshot: package,
          appNameSnapshot: app?.appName ?? package,
          eventType: ActivityLog.eventBlockedAttempt,
          outcome: raw['outcome'] is String
              ? raw['outcome'] as String
              : ActivityLog.outcomeConfirmed,
          details: raw['details'] is String ? raw['details'] as String : null,
          attemptedAt: _safeDate(raw['timestampMs']),
        ),
      );
      _activityLogs.removeAt(0);
    }

    // Shares a gate with TemporaryUnlockService.unlock so a retained, stale
    // revocation cannot be sent after a newer grant has been confirmed.
    await _operations.run(() async {
      _revocations.addAll(await unlocks.expireOutdatedUnlocks());
      for (final package in List.of(_revocations)) {
        if (await unlocks.getActiveUnlockForPackage(package) != null) {
          _revocations.remove(package);
          continue;
        }
        if (!await channel.revokeTemporaryUnlock(package)) {
          throw StateError(
            'Native temporary unlock revocation was not confirmed',
          );
        }
        _revocations.remove(package);
      }
    });
  }

  DateTime _safeDate(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value > 8640000000000000) {
      return DateTime.now();
    }
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
}

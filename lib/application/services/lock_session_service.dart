import '../../data/models/block_session.dart';
import '../../data/repositories/block_session_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/settings_repository.dart';

class LockSessionSetup {
  const LockSessionSetup({
    required this.message,
    required this.appName,
    required this.appId,
    required this.startEpochMs,
    required this.endEpochMs,
    required this.openedAtMs,
  });
  final String message;
  final String appName;
  final int? appId;
  final int startEpochMs;
  final int endEpochMs;
  final int openedAtMs;
}

class LockSessionService {
  const LockSessionService({
    required this.settingsRepository,
    required this.appRepository,
    this.sessionRepository,
  });
  final SettingsRepository settingsRepository;
  final BlockedAppRepository appRepository;
  final BlockSessionRepository? sessionRepository;

  Future<LockSessionSetup> initialize({
    String? packageName,
    String? appName,
    int? appId,
    int? startAtEpochMs,
    int? endAtEpochMs,
    required int Function() nowMs,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) throw StateError('Stale lock session');
    }

    final message = await settingsRepository.getCustomLockMessage();
    checkCancelled();
    final now = nowMs();
    var resolvedName = appName ?? packageName ?? 'Aplikasi Dibatasi';
    var resolvedId = appId;
    if ((appName == null ||
            appName.isEmpty ||
            appName == 'Aplikasi Dibatasi') &&
        packageName != null &&
        packageName.isNotEmpty) {
      try {
        final app = await appRepository.getAppByPackageName(packageName);
        resolvedName = app?.appName ?? resolvedName;
        if (resolvedId == null || resolvedId <= 0) resolvedId = app?.id;
      } catch (_) {
        // An unavailable display name must not bypass the waiting period.
      }
    }
    checkCancelled();

    var start = startAtEpochMs ?? now;
    var end = endAtEpochMs;
    if (end == null) {
      final session = packageName != null && packageName.isNotEmpty
          ? await sessionRepository?.getActiveSessionForPackage(packageName)
          : null;
      checkCancelled();
      if (session != null && session.endAt.millisecondsSinceEpoch > now) {
        start = session.startAt.millisecondsSinceEpoch;
        end = session.endAt.millisecondsSinceEpoch;
      } else {
        final waitingSeconds = await settingsRepository
            .getWaitingDurationSeconds();
        checkCancelled();
        end = start + (waitingSeconds > 0 ? waitingSeconds : 1) * 1000;
        if (packageName != null &&
            packageName.isNotEmpty &&
            sessionRepository != null) {
          await sessionRepository!.createSession(
            BlockSession(
              packageName: packageName,
              startAt: DateTime.fromMillisecondsSinceEpoch(start),
              endAt: DateTime.fromMillisecondsSinceEpoch(end),
              status: BlockSession.statusActive,
              createdAt: DateTime.fromMillisecondsSinceEpoch(now),
            ),
          );
        }
      }
    }
    checkCancelled();
    return LockSessionSetup(
      message: message,
      appName: resolvedName,
      appId: resolvedId,
      startEpochMs: start,
      endEpochMs: end,
      openedAtMs: now,
    );
  }
}

class LockCountdownTick {
  const LockCountdownTick(this.remainingSeconds, this.tamperingDetected);
  final int remainingSeconds;
  final bool tamperingDetected;
}

/// Wall-clock countdown with the existing monotonic anti-tamper thresholds.
/// Callers reset their stopwatch whenever [LockCountdownTick.tamperingDetected].
class LockCountdownPolicy {
  LockCountdownPolicy({
    required this.startEpochMs,
    required this.endEpochMs,
    required int openedAtMs,
  }) : _openedAtMs = openedAtMs,
       _lastObservedMs = openedAtMs {
    final duration = ((endEpochMs - startEpochMs) + 999) ~/ 1000;
    initialDurationSeconds = duration > 0 ? duration : 300;
  }

  int startEpochMs;
  int endEpochMs;
  late final int initialDurationSeconds;
  int _openedAtMs;
  int _lastObservedMs;

  LockCountdownTick tick({
    required int nowMs,
    required int monotonicElapsedMs,
  }) {
    final backward =
        nowMs < _lastObservedMs - 3000 || nowMs < startEpochMs - 3000;
    final forward =
        nowMs - _openedAtMs > monotonicElapsedMs + 5000 &&
        monotonicElapsedMs < initialDurationSeconds * 1000 - 2000;
    if (backward || forward) {
      startEpochMs = nowMs;
      endEpochMs = nowMs + initialDurationSeconds * 1000;
      _openedAtMs = nowMs;
      _lastObservedMs = nowMs;
      return LockCountdownTick(initialDurationSeconds, true);
    }
    _lastObservedMs = nowMs;
    final diff = endEpochMs - nowMs;
    return LockCountdownTick(diff > 0 ? (diff + 999) ~/ 1000 : 0, false);
  }
}

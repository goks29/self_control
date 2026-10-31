import 'dart:developer' as developer;

import '../../core/platform/blocking_platform_channel.dart';
import '../../data/models/activity_log.dart';
import '../../data/models/temporary_unlock.dart';
import '../../data/repositories/activity_log_repository.dart';
import '../../data/repositories/block_session_repository.dart';
import '../../data/repositories/blocked_app_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/temporary_unlock_repository.dart';
import 'blocking_operation_queue.dart';

class TemporaryUnlockException implements Exception {
  const TemporaryUnlockException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Coordinates a persisted grant with native enforcement. Success is only
/// committed after native confirmation; compensations are independent so a
/// database error never prevents an attempted native revocation.
class TemporaryUnlockService {
  TemporaryUnlockService({
    required this.settingsRepository,
    required this.unlockRepository,
    required this.appRepository,
    required this.logRepository,
    required this.platformChannel,
    this.sessionRepository,
    BlockingOperationQueue? operationQueue,
  }) : _operations = operationQueue ?? BlockingOperationQueue.shared;

  final SettingsRepository settingsRepository;
  final TemporaryUnlockRepository unlockRepository;
  final BlockedAppRepository appRepository;
  final ActivityLogRepository logRepository;
  final BlockingPlatformChannel platformChannel;
  final BlockSessionRepository? sessionRepository;
  final BlockingOperationQueue _operations;

  /// Returns a non-fatal audit warning if access was granted but logging failed.
  ///
  /// The whole grant, including rollback and audit handling, is serialized with
  /// runtime expiry/revocation decisions.
  Future<String?> unlock({
    required String password,
    required String? packageName,
    required String? appName,
    required int? appId,
    required int durationSeconds,
    bool Function()? isCancelled,
  }) {
    return _operations.run(
      () => _unlock(
        password: password,
        packageName: packageName,
        appName: appName,
        appId: appId,
        durationSeconds: durationSeconds,
        isCancelled: isCancelled,
      ),
    );
  }

  Future<String?> _unlock({
    required String password,
    required String? packageName,
    required String? appName,
    required int? appId,
    required int durationSeconds,
    bool Function()? isCancelled,
  }) async {
    void checkCancelled() {
      if (isCancelled?.call() ?? false) {
        throw const TemporaryUnlockException('Permintaan dibatalkan.');
      }
    }

    checkCancelled();
    final valid = await settingsRepository.verifyPassword(password);
    checkCancelled();
    if (!valid) {
      try {
        await logRepository.logEvent(
          ActivityLog(
            appId: appId,
            packageNameSnapshot: packageName ?? 'unknown.app',
            appNameSnapshot: appName ?? 'Aplikasi',
            eventType: ActivityLog.eventPasswordFailed,
            attemptedAt: DateTime.now(),
          ),
        );
      } catch (error, stackTrace) {
        // Log only the error type: repository messages may contain user input.
        developer.log(
          'password_failure_audit_write_failed',
          name: 'self_control.temporary_unlock',
          level: 900,
          error: error.runtimeType.toString(),
          stackTrace: stackTrace,
        );
      }
      throw const TemporaryUnlockException(
        'Password salah. Silakan coba lagi.',
      );
    }

    final package = packageName?.trim();
    if (package == null || package.isEmpty || package == 'unknown.app') {
      throw const TemporaryUnlockException(
        'Aplikasi tidak dikenali. Tutup lalu buka kembali aplikasi yang dibatasi.',
      );
    }
    if (durationSeconds <= 0) {
      throw const TemporaryUnlockException(
        'Pilih durasi buka akses yang valid.',
      );
    }
    var effectiveAppId = appId;
    if (effectiveAppId == null || effectiveAppId <= 0) {
      effectiveAppId = (await appRepository.getAppByPackageName(package))?.id;
    }
    checkCancelled();
    if (effectiveAppId == null || effectiveAppId <= 0) {
      throw const TemporaryUnlockException(
        'Aplikasi belum tersimpan. Pilih kembali aplikasi di daftar pembatasan lalu coba lagi.',
      );
    }

    final now = DateTime.now();
    final endAt = now.add(Duration(seconds: durationSeconds));
    final int unlockId;
    try {
      unlockId = await unlockRepository.createUnlock(
        TemporaryUnlock(
          appId: effectiveAppId,
          startAt: now,
          endAt: endAt,
          status: TemporaryUnlock.statusActive,
          createdAt: now,
        ),
      );
    } catch (_) {
      throw const TemporaryUnlockException(
        'Gagal menyimpan buka akses. Periksa ruang penyimpanan lalu coba lagi.',
      );
    }

    var nativeAttempted = false;
    var nativeConfirmed = false;
    try {
      checkCancelled();
      nativeAttempted = true;
      final synced = await platformChannel.syncTemporaryUnlock(
        packageName: package,
        durationSeconds: durationSeconds,
        expiresAtEpochMs: endAt.millisecondsSinceEpoch,
      );
      if (!synced) {
        throw const TemporaryUnlockException(
          'Gagal membuka akses. Periksa layanan aksesibilitas di Pengaturan lalu coba lagi.',
        );
      }
      nativeConfirmed = true;
      checkCancelled();
      await sessionRepository?.completeActiveSessionsForPackage(package);
    } catch (error) {
      var rollbackFailed = false;
      try {
        await unlockRepository.updateUnlockStatus(
          unlockId,
          TemporaryUnlock.statusRevoked,
        );
      } catch (_) {
        rollbackFailed = true;
      }
      if (nativeAttempted) {
        try {
          if (!await platformChannel.revokeTemporaryUnlock(package)) {
            rollbackFailed = true;
          }
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (rollbackFailed) {
        throw const TemporaryUnlockException(
          'Buka akses gagal dan pembatalan belum terkonfirmasi. Tutup aplikasi tujuan, periksa layanan aksesibilitas dan penyimpanan, lalu coba lagi.',
        );
      }
      if (error is TemporaryUnlockException) rethrow;
      if (!nativeConfirmed) {
        throw const TemporaryUnlockException(
          'Gagal membuka akses. Periksa layanan aksesibilitas di Pengaturan lalu coba lagi.',
        );
      }
      throw const TemporaryUnlockException(
        'Gagal menyelesaikan sesi. Akses telah dibatalkan; coba lagi.',
      );
    }

    try {
      await logRepository.logEvent(
        ActivityLog(
          appId: effectiveAppId,
          packageNameSnapshot: package,
          appNameSnapshot: appName ?? 'Aplikasi',
          eventType: ActivityLog.eventTemporaryUnlockStarted,
          attemptedAt: now,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'temporary_unlock_audit_write_failed',
        name: 'self_control.temporary_unlock',
        level: 900,
        error: error.runtimeType.toString(),
        stackTrace: stackTrace,
      );
      // The grant is already committed. An audit failure must not invite a
      // duplicate grant or pretend native access was rolled back.
      return 'Akses terbuka, tetapi riwayat gagal disimpan. Periksa penyimpanan.';
    }
    return null;
  }
}

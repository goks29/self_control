import 'package:sqflite/sqflite.dart';

import '../../core/platform/blocking_platform_channel.dart';
import '../../data/database/app_database.dart';

/// Coordinates destructive maintenance with native blocking state.
///
/// Failed native acknowledgements throw before local data is deleted. Native
/// state may already be partially cleared; callers must report failure and may
/// retry, rather than claiming the database was reset.
class DatabaseMaintenanceService {
  DatabaseMaintenanceService({required this.database, required this.channel});

  final AppDatabase database;
  final BlockingPlatformChannel channel;

  Future<DatabaseIntegrityResult> verifyIntegrity({bool full = true}) {
    return database.verifyIntegrity(full: full);
  }

  Future<Database> resetToDefaults({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    await _clearNativeState();
    return database.resetToDefaults(customPath: customPath, factory: factory);
  }

  /// Call immediately after opening the database, before repositories resume
  /// normal synchronization. No-op for a normal open; failures propagate so the
  /// root guard can offer a retry. This never deletes the recovered database.
  Future<void> synchronizeAfterRecovery() async {
    if (!database.recoveredOnOpen) return;
    await _clearNativeState();
  }

  Future<void> _clearNativeState() async {
    final apps = await channel.syncBlockedApps(const []);
    if (apps['status'] != 'success' || apps['syncedCount'] != 0) {
      throw StateError('Native blocked apps reset was not confirmed');
    }
    final sessions = await channel.syncActiveSessions(
      isStrictSessionActive: false,
    );
    if (!sessions) {
      throw StateError('Native active sessions reset was not confirmed');
    }
  }
}

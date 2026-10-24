import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/data/repositories/activity_log_repository.dart';
import 'package:self_control/data/repositories/blocked_app_repository.dart';
import 'package:self_control/data/repositories/settings_repository.dart';
import 'package:self_control/data/repositories/temporary_unlock_repository.dart';

void setupTestFonts() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel(BlockingPlatformChannel.channelName),
    (MethodCall call) async {
      switch (call.method) {
        case 'getBlockingCapability':
          return {'mode': 'standard', 'serviceStatus': 'disabled', 'limitations': <String>[]};
        case 'getAccessibilityStatus':
          return 'disabled';
        case 'openAccessibilitySettings':
          return true;
        case 'getInstalledApps':
          return <Map<String, dynamic>>[];
        case 'syncBlockedApps':
          return {'syncedCount': 0, 'status': 'success'};
        case 'syncTemporaryUnlock':
          return {'status': 'success'};
        case 'revokeTemporaryUnlock':
          return {'status': 'success'};
        case 'syncActiveSessions':
          return {'status': 'success'};
        case 'consumePendingBootEvents':
          return <int>[];
        default:
          return null;
      }
    },
  );
}

class FakeBlockedAppRepository implements BlockedAppRepository {
  final List<BlockedApp> apps;

  FakeBlockedAppRepository([List<BlockedApp>? initialApps])
      : apps = initialApps != null ? List.from(initialApps) : [];

  @override
  Future<List<BlockedApp>> getAllApps() async => List.unmodifiable(apps);

  @override
  Future<List<BlockedApp>> getSelectedApps() async =>
      apps.where((a) => a.isSelected).toList();

  @override
  Future<BlockedApp?> getAppByPackageName(String packageName) async {
    try {
      return apps.firstWhere((a) => a.packageName == packageName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveApps(List<BlockedApp> newApps) async {
    for (final app in newApps) {
      final index = apps.indexWhere((a) => a.packageName == app.packageName);
      if (index != -1) {
        apps[index] = app;
      } else {
        apps.add(app);
      }
    }
  }

  @override
  Future<void> setAppSelected(String packageName, bool isSelected) async {
    final index = apps.indexWhere((a) => a.packageName == packageName);
    if (index != -1) {
      apps[index] = apps[index].copyWith(isSelected: isSelected);
    }
  }
}

class FakeActivityLogRepository implements ActivityLogRepository {
  final List<ActivityLog> logs = [];

  @override
  Future<void> logEvent(ActivityLog log) async {
    logs.add(log);
  }

  @override
  Future<List<ActivityLog>> getLogs({int? limit, int? offset}) async {
    var result = List<ActivityLog>.from(logs.reversed);
    if (offset != null) {
      result = result.skip(offset).toList();
    }
    if (limit != null) {
      result = result.take(limit).toList();
    }
    return result;
  }

  @override
  Future<Map<String, int>> getAttemptCountsByPackage() async {
    final counts = <String, int>{};
    for (final log in logs) {
      if (log.eventType == ActivityLog.eventBlockedAttempt) {
        counts[log.packageNameSnapshot] = (counts[log.packageNameSnapshot] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  Future<void> clearAllLogs() async {
    logs.clear();
  }
}

class FakeSettingsRepository implements SettingsRepository {
  final Map<String, String> _storage = {};
  String? _expectedPassword;

  FakeSettingsRepository({
    Map<String, String>? initialSettings,
    String? expectedPassword,
  }) {
    if (initialSettings != null) {
      _storage.addAll(initialSettings);
    }
    _expectedPassword = expectedPassword;
    if (_expectedPassword != null) {
      _storage['password_hash'] = 'hashed_$_expectedPassword';
      _storage['password_salt'] = 'salt123';
    }
  }

  @override
  Future<String?> getSetting(String key) async => _storage[key];

  @override
  Future<void> setSetting(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<int> getWaitingDurationSeconds() async {
    final val = _storage['waiting_duration_seconds'];
    return val != null ? int.tryParse(val) ?? 300 : 300;
  }

  @override
  Future<String> getCustomLockMessage() async {
    return _storage['custom_lock_message'] ?? 'Tetap fokus pada tujuanmu.';
  }

  @override
  Future<bool> verifyPassword(String plainPassword) async {
    if (_expectedPassword == null) return false;
    return plainPassword == _expectedPassword;
  }

  @override
  Future<void> setPassword(String plainPassword) async {
    _expectedPassword = plainPassword;
    _storage['password_hash'] = 'hashed_$plainPassword';
    _storage['password_salt'] = 'random_salt';
  }

  @override
  Future<int> getDefaultUnlockDurationSeconds() async {
    final val = _storage['default_unlock_duration_seconds'];
    return val != null ? int.tryParse(val) ?? 600 : 600;
  }
}

class FakeTemporaryUnlockRepository implements TemporaryUnlockRepository {
  final List<TemporaryUnlock> unlocks = [];
  int _nextId = 1;

  @override
  Future<TemporaryUnlock?> getActiveUnlockForApp(int appId) async {
    try {
      return unlocks.firstWhere((u) => u.appId == appId && u.status == TemporaryUnlock.statusActive);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<TemporaryUnlock?> getActiveUnlockForPackage(String packageName) async {
    return null;
  }

  @override
  Future<int> createUnlock(TemporaryUnlock unlock) async {
    final id = _nextId++;
    unlocks.add(unlock.copyWith(id: id));
    return id;
  }

  @override
  Future<void> updateUnlockStatus(int unlockId, String status) async {
    final index = unlocks.indexWhere((u) => u.id == unlockId);
    if (index != -1) {
      unlocks[index] = unlocks[index].copyWith(status: status);
    }
  }

  @override
  Future<List<String>> expireOutdatedUnlocks() async {
    final now = DateTime.now();
    final expired = <String>[];
    for (int i = 0; i < unlocks.length; i++) {
      if (unlocks[i].status == TemporaryUnlock.statusActive && unlocks[i].endAt.isBefore(now)) {
        unlocks[i] = unlocks[i].copyWith(status: TemporaryUnlock.statusExpired);
      }
    }
    return expired;
  }
}

class FakeBlockingPlatformChannel extends BlockingPlatformChannel {
  FakeBlockingPlatformChannel({
    this.accessibilityStatus = 'disabled',
    this.installedApps = const [],
  });

  String accessibilityStatus;
  List<Map<String, dynamic>> installedApps;
  bool openSettingsCalled = false;
  List<String> lastSyncedPackages = [];

  @override
  Future<String> getAccessibilityStatus() async => accessibilityStatus;

  @override
  Future<bool> openAccessibilitySettings() async {
    openSettingsCalled = true;
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps() async => installedApps;

  @override
  Future<Map<String, dynamic>> syncBlockedApps(List<String> packageNames) async {
    lastSyncedPackages = List.from(packageNames);
    return {'syncedCount': packageNames.length, 'status': 'success'};
  }

  @override
  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async => true;

  @override
  Future<bool> revokeTemporaryUnlock(String packageName) async => true;

  @override
  Future<bool> syncActiveSessions({
    required bool isStrictSessionActive,
    int? sessionEndEpochMs,
    Map<String, dynamic>? activeSchedule,
  }) async => true;

  @override
  Future<List<int>> consumePendingBootEvents() async => <int>[];
}

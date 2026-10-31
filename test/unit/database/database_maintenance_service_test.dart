import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/database_maintenance_service.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:sqflite/sqflite.dart';

class _Database extends AppDatabase {
  final events = <String>[];
  bool recovered = false;
  @override
  bool get recoveredOnOpen => recovered;
  @override
  Future<Database> resetToDefaults({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    events.add('delete');
    return _Handle();
  }
}

class _Handle implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel extends BlockingPlatformChannel {
  _Channel(this.events);
  final List<String> events;
  Map<String, dynamic> appsResult = {'status': 'success', 'syncedCount': 0};
  bool sessionsResult = true;
  bool throwOnApps = false;
  @override
  Future<Map<String, dynamic>> syncBlockedApps(
    List<String> packageNames,
  ) async {
    expect(packageNames, isEmpty);
    events.add('apps');
    if (throwOnApps) throw StateError('native unavailable');
    return appsResult;
  }

  @override
  Future<bool> syncActiveSessions({
    required bool isStrictSessionActive,
    int? sessionEndEpochMs,
    Map<String, dynamic>? activeSchedule,
  }) async {
    expect(isStrictSessionActive, isFalse);
    expect(sessionEndEpochMs, isNull);
    expect(activeSchedule, isNull);
    events.add('sessions');
    return sessionsResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native apps and sessions are acknowledged before destructive reset',
    () async {
      final db = _Database();
      final service = DatabaseMaintenanceService(
        database: db,
        channel: _Channel(db.events),
      );
      expect(await service.resetToDefaults(), isA<Database>());
      expect(db.events, ['apps', 'sessions', 'delete']);
    },
  );

  for (final result in <Map<String, dynamic>>[
    {},
    {'status': 'error', 'syncedCount': 0},
    {'status': 'success'},
    {'status': 'success', 'syncedCount': 1},
  ]) {
    test(
      'unconfirmed blocked apps reset preserves local database: $result',
      () async {
        final db = _Database();
        final channel = _Channel(db.events)..appsResult = result;
        final service = DatabaseMaintenanceService(
          database: db,
          channel: channel,
        );
        await expectLater(service.resetToDefaults(), throwsStateError);
        expect(db.events, isNot(contains('delete')));
      },
    );
  }

  test('unconfirmed sessions reset preserves local database', () async {
    final db = _Database();
    final channel = _Channel(db.events)..sessionsResult = false;
    final service = DatabaseMaintenanceService(database: db, channel: channel);
    await expectLater(service.resetToDefaults(), throwsStateError);
    expect(db.events, ['apps', 'sessions']);
  });

  test('native exceptions propagate without destructive reset', () async {
    final db = _Database();
    final channel = _Channel(db.events)..throwOnApps = true;
    final service = DatabaseMaintenanceService(database: db, channel: channel);
    await expectLater(service.resetToDefaults(), throwsStateError);
    expect(db.events, ['apps']);
  });

  test('missing platform implementation cannot authorize deletion', () async {
    final db = _Database();
    final service = DatabaseMaintenanceService(
      database: db,
      channel: BlockingPlatformChannel(
        const MethodChannel('maintenance_missing_plugin'),
      ),
    );
    await expectLater(service.resetToDefaults(), throwsStateError);
    expect(db.events, isEmpty);
  });

  test(
    'recovery sync is explicit and does not reset the fresh database',
    () async {
      final db = _Database()..recovered = true;
      final service = DatabaseMaintenanceService(
        database: db,
        channel: _Channel(db.events),
      );
      await service.synchronizeAfterRecovery();
      expect(db.events, ['apps', 'sessions']);
    },
  );

  test('normal open never clears native state', () async {
    final db = _Database();
    final service = DatabaseMaintenanceService(
      database: db,
      channel: _Channel(db.events),
    );
    await service.synchronizeAfterRecovery();
    expect(db.events, isEmpty);
  });

  test('failed recovery sync is surfaced and can be retried', () async {
    final db = _Database()..recovered = true;
    final channel = _Channel(db.events)..sessionsResult = false;
    final service = DatabaseMaintenanceService(database: db, channel: channel);
    await expectLater(service.synchronizeAfterRecovery(), throwsStateError);
    channel.sessionsResult = true;
    await service.synchronizeAfterRecovery();
    expect(db.events, ['apps', 'sessions', 'apps', 'sessions']);
  });
}

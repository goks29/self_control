import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/settings_service.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import 'package:self_control/presentation/widgets/app_button.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers.dart';

class ControlledSettingsRepository extends FakeSettingsRepository {
  bool failLoad = false;
  bool failSave = false;
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  int writes = 0;

  @override
  Future<int> getWaitingDurationSeconds() async {
    await loadGate?.future;
    if (failLoad) throw StateError('load failed');
    return super.getWaitingDurationSeconds();
  }

  @override
  Future<void> setSetting(String key, String value) async {
    writes++;
    await saveGate?.future;
    if (failSave) throw StateError('save failed');
    await super.setSetting(key, value);
  }
}

class ControlledMaintenanceDatabase extends FakeAppDatabase {
  Completer<void>? integrityGate;
  Completer<void>? resetGate;
  int checks = 0;
  int resets = 0;
  bool failReset = false;
  final List<String> events = [];

  @override
  Future<DatabaseIntegrityResult> verifyIntegrity({
    bool full = false,
    Database? targetDb,
  }) async {
    checks++;
    await integrityGate?.future;
    return super.verifyIntegrity(full: full, targetDb: targetDb);
  }

  @override
  Future<Database> resetToDefaults({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    resets++;
    events.add('database');
    await resetGate?.future;
    if (failReset) throw StateError('reset failed');
    return super.resetToDefaults(customPath: customPath, factory: factory);
  }
}

class RecordingResetChannel extends BlockingPlatformChannel {
  RecordingResetChannel(this.events);

  final List<String> events;
  bool appsConfirmed = true;
  bool sessionsConfirmed = true;

  @override
  Future<Map<String, dynamic>> syncBlockedApps(
    List<String> packageNames,
  ) async {
    expect(packageNames, isEmpty);
    events.add('apps');
    return {'status': appsConfirmed ? 'success' : 'error', 'syncedCount': 0};
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
    return sessionsConfirmed;
  }
}

Future<void> mountSettings(
  WidgetTester tester,
  ControlledSettingsRepository repository, {
  ControlledMaintenanceDatabase? database,
  BlockingPlatformChannel? channel,
  VoidCallback? onDataReset,
}) async {
  tester.view.physicalSize = const Size(1000, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        settingsRepository: repository,
        appDatabase: database,
        platformChannel: channel,
        onDataReset: onDataReset,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppButton button(WidgetTester tester, String label) => tester.widget<AppButton>(
  find.byWidgetPredicate(
    (widget) => widget is AppButton && widget.text == label,
  ),
);

void main() {
  setUpAll(setupTestFonts);

  testWidgets('load failure is visible and releases loading for retry', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository()..failLoad = true;
    await mountSettings(tester, repository);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Gagal memuat pengaturan'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    repository.failLoad = false;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Simpan Pengaturan'), findsOneWidget);
  });

  testWidgets('save failure is visible and can be retried', (tester) async {
    final repository = ControlledSettingsRepository()..failSave = true;
    await mountSettings(tester, repository);
    await tester.tap(find.text('Simpan Pengaturan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Gagal menyimpan pengaturan'), findsOneWidget);
    expect(button(tester, 'Simpan Pengaturan').isLoading, isFalse);
    repository.failSave = false;
    await tester.tap(find.text('Simpan Pengaturan'));
    await tester.pumpAndSettle();
    expect(find.text('Pengaturan berhasil disimpan.'), findsOneWidget);
  });

  testWidgets(
    'save snapshots fields and blocks duplicate and maintenance operations',
    (tester) async {
      final repository = ControlledSettingsRepository()
        ..saveGate = Completer<void>();
      final database = ControlledMaintenanceDatabase();
      await mountSettings(tester, repository, database: database);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Original message',
      );
      final save = button(tester, 'Simpan Pengaturan').onPressed!;
      final reset = button(tester, 'Reset Darurat').onPressed!;
      final check = button(tester, 'Cek Integritas').onPressed!;
      save();
      save();
      reset();
      check();
      await tester.pump();
      expect(repository.writes, 1);
      expect(database.checks, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Changed while saving',
      );
      repository.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(await repository.getCustomLockMessage(), 'Original message');
    },
  );

  testWidgets('integrity check reserves operation until completion', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase()
      ..integrityGate = Completer<void>();
    await mountSettings(tester, repository, database: database);
    final check = button(tester, 'Cek Integritas').onPressed!;
    final reset = button(tester, 'Reset Darurat').onPressed!;
    final save = button(tester, 'Simpan Pengaturan').onPressed!;
    check();
    check();
    reset();
    save();
    await tester.pump();
    expect(database.checks, 1);
    expect(repository.writes, 0);
    expect(find.byType(AlertDialog), findsNothing);
    database.integrityGate!.complete();
    await tester.pumpAndSettle();
    expect(button(tester, 'Reset Darurat').onPressed, isNotNull);
  });

  testWidgets('confirmation reserves operation and cancellation releases it', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase();
    await mountSettings(tester, repository, database: database);
    final reset = button(tester, 'Reset Darurat').onPressed!;
    final save = button(tester, 'Simpan Pengaturan').onPressed!;
    final check = button(tester, 'Cek Integritas').onPressed!;
    reset();
    reset();
    save();
    check();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.writes, 0);
    expect(database.checks, 0);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(button(tester, 'Simpan Pengaturan').onPressed, isNotNull);
    expect(database.resets, 0);
  });

  testWidgets(
    'completing password save after disposal never accesses controllers',
    (tester) async {
      final repository = ControlledSettingsRepository()
        ..saveGate = Completer<void>();
      await mountSettings(tester, repository);
      await tester.enterText(find.byType(TextFormField).at(1), '1234');
      await tester.enterText(find.byType(TextFormField).at(2), '1234');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      repository.saveGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(await repository.verifyPassword('1234'), isTrue);
    },
  );

  testWidgets('repeated confirmation cannot pop the settings route', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                        settingsRepository: repository,
                        appDatabase: database,
                        platformChannel: RecordingResetChannel(database.events),
                      ),
                    ),
                  );
                },
                child: const Text('Open settings'),
              ),
            );
          },
        ),
      ),
    );
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Darurat'));
    await tester.pumpAndSettle();
    final confirm = button(tester, 'Reset').onPressed!;
    confirm();
    confirm();
    await tester.pumpAndSettle();
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(database.resets, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset confirms native state before deleting and notifying', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase();
    final channel = RecordingResetChannel(database.events);
    await mountSettings(
      tester,
      repository,
      database: database,
      channel: channel,
      onDataReset: () => database.events.add('notified'),
    );
    await tester.tap(find.text('Reset Darurat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(database.events, ['apps', 'sessions', 'database', 'notified']);
    expect(
      find.text('Seluruh pengaturan dan data berhasil direset.'),
      findsOneWidget,
    );
  });

  for (final failure in ['apps', 'sessions', 'database']) {
    testWidgets('$failure reset failure is visible and does not notify', (
      tester,
    ) async {
      final repository = ControlledSettingsRepository();
      final database = ControlledMaintenanceDatabase()
        ..failReset = failure == 'database';
      final channel = RecordingResetChannel(database.events)
        ..appsConfirmed = failure != 'apps'
        ..sessionsConfirmed = failure != 'sessions';
      var notifications = 0;
      await mountSettings(
        tester,
        repository,
        database: database,
        channel: channel,
        onDataReset: () => notifications++,
      );
      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(notifications, 0);
      expect(database.resets, failure == 'database' ? 1 : 0);
      expect(find.textContaining('Gagal mereset data'), findsOneWidget);
      expect(button(tester, 'Reset Darurat').onPressed, isNotNull);
    });
  }

  testWidgets('reset notifies before reload, even when reload fails', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase();
    var notifications = 0;
    await mountSettings(
      tester,
      repository,
      database: database,
      channel: RecordingResetChannel(database.events),
      onDataReset: () => notifications++,
    );
    repository.loadGate = Completer<void>();
    repository.failLoad = true;
    await tester.tap(find.text('Reset Darurat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(database.resets, 1);
    expect(notifications, 1);
    repository.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Gagal memuat pengaturan'), findsOneWidget);
    expect(find.textContaining('Gagal mereset data'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reset prevents overlapping actions and notifies after disposal',
    (tester) async {
      final repository = ControlledSettingsRepository();
      final database = ControlledMaintenanceDatabase()
        ..resetGate = Completer<void>();
      var notifications = 0;
      await mountSettings(
        tester,
        repository,
        database: database,
        channel: RecordingResetChannel(database.events),
        onDataReset: () => notifications++,
      );
      final reset = button(tester, 'Reset Darurat').onPressed!;
      final check = button(tester, 'Cek Integritas').onPressed!;
      final save = button(tester, 'Simpan Pengaturan').onPressed!;
      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      reset();
      check();
      save();
      await tester.pump();
      expect(database.events, ['apps', 'sessions', 'database']);
      expect(database.resets, 1);
      expect(database.checks, 0);
      expect(repository.writes, 0);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      database.resetGate!.complete();
      await tester.pumpAndSettle();
      expect(notifications, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirming after settings disposal never starts reset', (
    tester,
  ) async {
    final repository = ControlledSettingsRepository();
    final database = ControlledMaintenanceDatabase();
    final showSettings = ValueNotifier(true);
    addTearDown(showSettings.dispose);
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showSettings,
          builder: (_, visible, _) => visible
              ? SettingsScreen(
                  settingsRepository: repository,
                  appDatabase: database,
                  platformChannel: RecordingResetChannel(database.events),
                )
              : const Scaffold(body: Text('Settings removed')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Darurat'));
    await tester.pumpAndSettle();
    showSettings.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(database.events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test(
    'settings service loads a complete snapshot and normalizes saved message',
    () async {
      final repository = ControlledSettingsRepository();
      final service = SettingsService(repository: repository);
      await service.save(
        waitingDurationSeconds: 60,
        customLockMessage: '  Focus  ',
        defaultUnlockDurationSeconds: 900,
        password: '1234',
      );
      final settings = await service.load();
      expect(settings.waitingDurationSeconds, 60);
      expect(settings.customLockMessage, 'Focus');
      expect(settings.defaultUnlockDurationSeconds, 900);
      expect(settings.hasExistingPassword, isTrue);
      expect(await repository.verifyPassword('1234'), isTrue);
      await service.save(
        waitingDurationSeconds: 300,
        customLockMessage: '  ',
        defaultUnlockDurationSeconds: 600,
        password: '',
      );
      expect(
        (await service.load()).customLockMessage,
        'Tetap fokus pada tujuanmu.',
      );
      expect(await repository.verifyPassword('1234'), isTrue);
    },
  );
}

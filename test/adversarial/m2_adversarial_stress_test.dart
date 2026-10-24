import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/database/app_database.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/app_setting.dart';
import 'package:self_control/data/repositories/activity_log_repository_impl.dart';
import 'package:self_control/data/repositories/settings_repository_impl.dart';
import 'package:self_control/presentation/home/dashboard_screen.dart';
import 'package:self_control/presentation/application/application_selection_screen.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/core/theme/app_theme.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: child,
    );
  }

  // =========================================================================
  // TASK 1: DASHBOARD METRICS AGGREGATION STRESS TEST (1,000 LOGS / 10 APPS)
  // =========================================================================
  group('Task 1: Dashboard Metrics Aggregation Stress Test', () {
    late AppDatabase appDatabase;
    late Database db;
    late ActivityLogRepositoryImpl activityRepo;

    setUp(() async {
      appDatabase = AppDatabase.instance;
      db = await appDatabase.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      activityRepo = ActivityLogRepositoryImpl(db: db);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('Insert 1,000 activity logs across 10 apps and verify SQL aggregation', () async {
      final appDistributions = <String, int>{
        'com.social.insta': 300,
        'com.video.tok': 200,
        'com.stream.tube': 150,
        'com.chat.tele': 100,
        'com.game.gacha': 80,
        'com.browse.chrome': 60,
        'com.news.feed': 40,
        'com.shop.store': 30,
        'com.music.beat': 25,
        'com.forum.thread': 15,
      };

      final totalExpected = appDistributions.values.fold<int>(0, (sum, val) => sum + val);
      expect(totalExpected, equals(1000));

      final baseTime = DateTime(2026, 10, 24, 10, 0, 0);

      // Batch insert 1,000 activity logs
      final batch = db.batch();
      int logIndex = 0;
      for (final entry in appDistributions.entries) {
        final pkg = entry.key;
        final count = entry.value;
        final appName = 'App ${pkg.split('.').last.toUpperCase()}';

        for (int i = 0; i < count; i++) {
          final log = ActivityLog(
            packageNameSnapshot: pkg,
            appNameSnapshot: appName,
            eventType: ActivityLog.eventBlockedAttempt,
            attemptedAt: baseTime.add(Duration(seconds: logIndex)),
          );
          batch.insert(AppDatabase.tableActivityLogs, log.toMap());
          logIndex++;
        }
      }
      await batch.commit(noResult: true);

      // Measure query execution time
      final stopwatch = Stopwatch()..start();
      final counts = await activityRepo.getAttemptCountsByPackage();
      stopwatch.stop();

      // Ensure aggregation query is sub-100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100),
          reason: 'Aggregation query exceeded 100ms budget: ${stopwatch.elapsedMilliseconds}ms');

      // Verify aggregation correctness
      expect(counts.length, equals(10));
      int totalAggregated = 0;
      for (final entry in appDistributions.entries) {
        expect(counts[entry.key], equals(entry.value),
            reason: 'Mismatch for package ${entry.key}');
        totalAggregated += counts[entry.key]!;
      }
      expect(totalAggregated, equals(1000));

      // Verify top package order
      final sortedPackages = counts.keys.toList()
        ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
      expect(sortedPackages.first, equals('com.social.insta'));
      expect(counts[sortedPackages.first], equals(300));
      expect(sortedPackages.last, equals('com.forum.thread'));
      expect(counts[sortedPackages.last], equals(15));
    });

    testWidgets('DashboardScreen renders 1,000 attempts without RenderFlex overflow in section header Row', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appDistributions = <String, int>{
        'com.social.insta': 300,
        'com.video.tok': 200,
        'com.stream.tube': 150,
        'com.chat.tele': 100,
        'com.game.gacha': 80,
        'com.browse.chrome': 60,
        'com.news.feed': 40,
        'com.shop.store': 30,
        'com.music.beat': 25,
        'com.forum.thread': 15,
      };

      final fakeRepo = FakeActivityLogRepository();
      final baseTime = DateTime(2026, 10, 24, 10, 0, 0);
      int logIndex = 0;
      for (final entry in appDistributions.entries) {
        final pkg = entry.key;
        final count = entry.value;
        final appName = 'App ${pkg.split('.').last.toUpperCase()}';

        for (int i = 0; i < count; i++) {
          fakeRepo.logs.add(
            ActivityLog(
              packageNameSnapshot: pkg,
              appNameSnapshot: appName,
              eventType: ActivityLog.eventBlockedAttempt,
              attemptedAt: baseTime.add(Duration(seconds: logIndex)),
            ),
          );
          logIndex++;
        }
      }

      FlutterErrorDetails? overflowDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.summary.toString().contains('RenderFlex overflowed')) {
          overflowDetails = details;
        } else {
          originalOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Measure widget render time
      final stopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        buildTestableWidget(
          DashboardScreen(activityLogRepository: fakeRepo),
        ),
      );
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000),
          reason: 'UI took over 1,000ms to pump DashboardScreen with 1,000 logs');

      // Verify metrics aggregated correctly
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('Total Percobaan Dicegah'), findsOneWidget);
      expect(find.text('10 aplikasi'), findsOneWidget);
      expect(find.text('300 kali'), findsOneWidget);
      expect(find.text('200 kali'), findsOneWidget);

      expect(overflowDetails, isNull,
          reason: 'Expected no RenderFlex overflow in dashboard_screen.dart:188');
    });

    testWidgets('DashboardScreen wide canvas (800dp) renders without overflow', (tester) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 2.0; // 800dp width
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeActivityLogRepository();
      fakeRepo.logs.add(
        ActivityLog(
          packageNameSnapshot: 'com.social.insta',
          appNameSnapshot: 'Instagram',
          eventType: ActivityLog.eventBlockedAttempt,
          attemptedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(
        buildTestableWidget(
          DashboardScreen(activityLogRepository: fakeRepo),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('1'), findsOneWidget);
    });
  });

  // =========================================================================
  // TASK 2: APPLICATION SELECTION SCREEN STRESS TEST (50 APPS, RAPID TOGGLE)
  // =========================================================================
  group('Task 2: ApplicationSelectionScreen Stress Test', () {
    late List<BlockedApp> test50Apps;

    setUp(() {
      test50Apps = List.generate(50, (i) {
        final indexStr = i.toString().padLeft(2, '0');
        return BlockedApp(
          id: i + 1,
          packageName: 'com.test.application$indexStr',
          appName: 'App $indexStr',
          isSelected: false,
          createdAt: DateTime(2026, 10, 24),
        );
      });
    });

    testWidgets('Rapid toggling of 50 apps maintains strict selection counter consistency', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeBlockedAppRepository(test50Apps);
      final fakeChannel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      await tester.pumpWidget(
        buildTestableWidget(
          ApplicationSelectionScreen(
            blockedAppRepository: fakeRepo,
            platformChannel: fakeChannel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 aplikasi dipilih'), findsOneWidget);

      // Fast rapid toggling across 10 visible apps
      for (int i = 0; i < 10; i++) {
        final indexStr = i.toString().padLeft(2, '0');
        await tester.tap(find.text('App $indexStr'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('10 aplikasi dipilih'), findsOneWidget);
      expect((await fakeRepo.getSelectedApps()).length, equals(10));

      // Rapidly toggle the same item 5 times
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('App 00'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // App 00 was toggled 5 times from true -> false -> true -> false -> true -> false
      expect(find.text('9 aplikasi dipilih'), findsOneWidget);
      expect((await fakeRepo.getSelectedApps()).length, equals(9));
    });

    testWidgets('Select All and Deselect All stress test on 50 apps without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeBlockedAppRepository(test50Apps);
      final fakeChannel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      await tester.pumpWidget(
        buildTestableWidget(
          ApplicationSelectionScreen(
            blockedAppRepository: fakeRepo,
            platformChannel: fakeChannel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      FlutterErrorDetails? overflowDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.summary.toString().contains('RenderFlex overflowed')) {
          overflowDetails = details;
        } else {
          originalOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      // Tap 'Pilih Semua'
      await tester.tap(find.text('Pilih Semua'));
      await tester.pumpAndSettle();

      expect(find.text('50 aplikasi dipilih'), findsOneWidget);
      expect(find.text('Batal Pilih Semua'), findsOneWidget);
      expect((await fakeRepo.getSelectedApps()).length, equals(50));

      expect(overflowDetails, isNull,
          reason: 'Expected no RenderFlex overflow in application_selection_screen.dart:183');

      // Tap 'Batal Pilih Semua'
      await tester.tap(find.text('Batal Pilih Semua'));
      await tester.pumpAndSettle();

      expect(find.text('0 aplikasi dipilih'), findsOneWidget);
      expect(find.text('Pilih Semua'), findsOneWidget);
      expect((await fakeRepo.getSelectedApps()).length, equals(0));
    });

    testWidgets('Search filtering adversarial edge cases (special chars, empty, no match, extreme length)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeBlockedAppRepository(test50Apps);
      final fakeChannel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      await tester.pumpWidget(
        buildTestableWidget(
          ApplicationSelectionScreen(
            blockedAppRepository: fakeRepo,
            platformChannel: fakeChannel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);

      // Edge Case 1: Regex special characters (must not crash with PatternSyntaxException)
      const regexChars = r'.*+?^${}()|[]\';
      await tester.enterText(searchField, regexChars);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Aplikasi "$regexChars" tidak ditemukan'), findsOneWidget);

      // Edge Case 2: Special injection characters and quotes
      const injectionString = "'; DROP TABLE blocked_apps; -- <script>";
      await tester.enterText(searchField, injectionString);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Aplikasi "$injectionString" tidak ditemukan'), findsOneWidget);

      // Edge Case 3: Emojis and multi-byte Unicode
      const unicodeString = '🔥🛡️测试مرحبا';
      await tester.enterText(searchField, unicodeString);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Aplikasi "$unicodeString" tidak ditemukan'), findsOneWidget);

      // Edge Case 4: Extreme length query (500 characters) - verify no layout overflow
      final extremeQuery = 'X' * 500;
      await tester.enterText(searchField, extremeQuery);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('tidak ditemukan'), findsOneWidget);

      // Edge Case 5: Clear button restores all 50 apps
      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();
      expect(find.text('0 aplikasi dipilih'), findsOneWidget);
      expect(find.text('App 00'), findsOneWidget);

      // Edge Case 6: Substring match case insensitivity
      await tester.enterText(searchField, 'app 05');
      await tester.pumpAndSettle();
      expect(find.text('App 05'), findsOneWidget);
      expect(find.text('App 06'), findsNothing);
    });

    testWidgets('Selection counter consistency when search filter is active', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeRepo = FakeBlockedAppRepository(test50Apps);
      final fakeChannel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');

      await tester.pumpWidget(
        buildTestableWidget(
          ApplicationSelectionScreen(
            blockedAppRepository: fakeRepo,
            platformChannel: fakeChannel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select App 01 and App 02
      await tester.tap(find.text('App 01'));
      await tester.pump();
      await tester.tap(find.text('App 02'));
      await tester.pumpAndSettle();
      expect(find.text('2 aplikasi dipilih'), findsOneWidget);

      // Filter search to 'App 01' only
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'App 01');
      await tester.pumpAndSettle();

      // Top counter MUST preserve global selection count (2), not just visible count
      expect(find.text('2 aplikasi dipilih'), findsOneWidget);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('2 aplikasi dipilih'), findsOneWidget);
    });
  });

  // =========================================================================
  // TASK 3: SETTINGS SCREEN STRESS TEST (EXTREME DURATIONS, PASSWORDS, MSG)
  // =========================================================================
  group('Task 3: SettingsScreen Stress Test', () {
    late AppDatabase appDatabase;
    late Database db;
    late SettingsRepositoryImpl settingsRepo;

    setUp(() async {
      appDatabase = AppDatabase.instance;
      db = await appDatabase.initDatabase(
        customPath: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      settingsRepo = SettingsRepositoryImpl(db: db);
    });

    tearDown(() async {
      await appDatabase.close();
    });

    test('SettingsRepository handles extreme wait duration inputs safely', () async {
      // Test negative duration
      await settingsRepo.setSetting(AppSetting.keyWaitingDurationSeconds, '-100');
      expect(await settingsRepo.getWaitingDurationSeconds(), equals(-100));

      // Test zero duration
      await settingsRepo.setSetting(AppSetting.keyWaitingDurationSeconds, '0');
      expect(await settingsRepo.getWaitingDurationSeconds(), equals(0));

      // Test extreme duration (1,000,000s)
      await settingsRepo.setSetting(AppSetting.keyWaitingDurationSeconds, '1000000');
      expect(await settingsRepo.getWaitingDurationSeconds(), equals(1000000));

      // Test corrupted non-integer value falls back to default 300
      await settingsRepo.setSetting(AppSetting.keyWaitingDurationSeconds, 'invalid_corrupted_number');
      expect(await settingsRepo.getWaitingDurationSeconds(), equals(AppSetting.defaultWaitingDurationSeconds));

      // Test corrupted default unlock duration falls back to default 600
      await settingsRepo.setSetting(AppSetting.keyDefaultUnlockDurationSeconds, 'corrupt');
      expect(await settingsRepo.getDefaultUnlockDurationSeconds(), equals(AppSetting.defaultUnlockDurationSeconds));
    });

    testWidgets('SettingsScreen loads with extreme wait durations (-60, 0, 1,000,000) without crashing', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSettingsRepo = FakeSettingsRepository(
        initialSettings: {
          AppSetting.keyWaitingDurationSeconds: '1000000',
          AppSetting.keyCustomLockMessage: 'Tetap fokus pada tujuanmu.',
          AppSetting.keyDefaultUnlockDurationSeconds: '600',
        },
      );

      await tester.pumpWidget(
        buildTestableWidget(
          SettingsScreen(settingsRepository: fakeSettingsRepo),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Durasi Tunggu Layar Kunci'), findsOneWidget);

      // Verify saving settings with extreme values succeeds
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan berhasil disimpan.'), findsOneWidget);
      expect(await fakeSettingsRepo.getWaitingDurationSeconds(), equals(1000000));
    });

    testWidgets('LockedScreen handles extreme 1,000,000s duration formatting without layout overflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSettingsRepo = FakeSettingsRepository(
        initialSettings: {
          AppSetting.keyWaitingDurationSeconds: '1000000',
        },
      );

      await tester.pumpWidget(
        buildTestableWidget(
          LockedScreen(
            packageName: 'com.distracting.app',
            appName: 'Distracting App',
            settingsRepository: fakeSettingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // 1,000,000 seconds = 16,666 minutes and 40 seconds -> '16666:40'
      expect(find.textContaining('16666:'), findsOneWidget);
    });

    testWidgets('SettingsScreen strictly validates password mismatch and short passwords (< 4 chars)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSettingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        buildTestableWidget(
          SettingsScreen(settingsRepository: fakeSettingsRepo),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      // index 0: custom message, index 1: password, index 2: confirm password
      final passwordField = textFields.at(1);
      final confirmPasswordField = textFields.at(2);

      // Test 1: Short password (< 4 chars)
      await tester.enterText(passwordField, '123');
      await tester.enterText(confirmPasswordField, '123');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Password minimal 4 karakter'), findsOneWidget);
      expect(await fakeSettingsRepo.getSetting(AppSetting.keyPasswordHash), isNull);

      // Test 2: Password mismatch
      await tester.enterText(passwordField, 'Secret1234');
      await tester.enterText(confirmPasswordField, 'Different5678');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi password tidak cocok'), findsOneWidget);
      expect(await fakeSettingsRepo.getSetting(AppSetting.keyPasswordHash), isNull);

      // Test 3: Matching valid password saves successfully
      await tester.enterText(confirmPasswordField, 'Secret1234');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan berhasil disimpan.'), findsOneWidget);
      expect(await fakeSettingsRepo.getSetting(AppSetting.keyPasswordHash), isNotNull);
      expect(find.text('Password sudah diatur'), findsOneWidget);
    });

    testWidgets('SettingsScreen custom message edge cases (special characters, empty fallback, whitespace)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeSettingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        buildTestableWidget(
          SettingsScreen(settingsRepository: fakeSettingsRepo),
        ),
      );
      await tester.pumpAndSettle();

      final customMsgField = find.byType(TextFormField).first;

      // Special characters, emojis, and quotes
      const specialMsg = '🔥 Focus Now! 🛑 "Stay Strong" & Win <3';
      await tester.enterText(customMsgField, specialMsg);
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan berhasil disimpan.'), findsOneWidget);
      expect(await fakeSettingsRepo.getCustomLockMessage(), equals(specialMsg));

      // Empty string falls back to default
      await tester.enterText(customMsgField, '');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(await fakeSettingsRepo.getCustomLockMessage(), equals('Tetap fokus pada tujuanmu.'));

      // Whitespace-only string trims and falls back to default
      await tester.enterText(customMsgField, '    \n\t   ');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(await fakeSettingsRepo.getCustomLockMessage(), equals('Tetap fokus pada tujuanmu.'));
    });

    test('FakeSettingsRepository verifyPassword returns false when unset matching production', () async {
      final fakeSettingsRepo = FakeSettingsRepository();
      expect(await fakeSettingsRepo.verifyPassword('anyPassword'), isFalse);
      expect(await fakeSettingsRepo.verifyPassword(''), isFalse);

      await fakeSettingsRepo.setPassword('validPass123');
      expect(await fakeSettingsRepo.verifyPassword('validPass123'), isTrue);
      expect(await fakeSettingsRepo.verifyPassword('wrongPassword'), isFalse);
    });
  });
}

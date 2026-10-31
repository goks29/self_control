import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/block_session.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/widgets/app_button.dart';

import '../test_helpers.dart';

class _Channel extends FakeBlockingPlatformChannel {
  bool nativeSuccess = false;
  bool launchSuccess = true;
  int grants = 0;
  int revocations = 0;

  @override
  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async {
    grants++;
    return nativeSuccess;
  }

  @override
  Future<bool> revokeTemporaryUnlock(String packageName) async {
    revocations++;
    return true;
  }

  @override
  Future<bool> launchTargetApp(String packageName) async => launchSuccess;
}

class _FailingUnlocks extends FakeTemporaryUnlockRepository {
  @override
  Future<int> createUnlock(TemporaryUnlock unlock) async =>
      throw StateError('disk full');
}

class _FailingAudit extends FakeActivityLogRepository {
  int attempts = 0;

  @override
  Future<void> logEvent(ActivityLog log) async {
    attempts++;
    throw StateError('audit unavailable');
  }
}

class _DelayedPassword extends FakeSettingsRepository {
  final verification = Completer<bool>();
  int attempts = 0;

  @override
  Future<bool> verifyPassword(String plainPassword) {
    attempts++;
    return verification.future;
  }
}

class _FailingSettings extends FakeSettingsRepository {
  bool fail = true;

  @override
  Future<String> getCustomLockMessage() async {
    if (fail) throw StateError('database unavailable');
    return 'Recovered';
  }
}

class _DelayedMessage extends FakeSettingsRepository {
  final firstMessage = Completer<String>();
  int reads = 0;

  @override
  Future<String> getCustomLockMessage() async {
    if (reads++ == 0) return firstMessage.future;
    return 'Current message';
  }
}

void main() {
  setUpAll(setupTestFonts);
  void regressionTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await body(tester);
    });
  }

  regressionTest(
    'tamper audit failure does not interrupt countdown reset or ticking',
    (tester) async {
      var now = 1000000;
      final logs = _FailingAudit();
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.test',
            appName: 'Test',
            startAtEpochMs: now,
            endAtEpochMs: now + 300000,
            nowMsProvider: () => now,
            autoOpenModal: false,
            settingsRepository: FakeSettingsRepository(),
            activityLogRepository: logs,
            blockedAppRepository: FakeBlockedAppRepository(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('05:00'), findsOneWidget);
      now -= 10000;
      final state =
          tester.state(find.byType(LockedScreen)) as WidgetsBindingObserver;
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(logs.attempts, 1);
      expect(find.text('05:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      now += 1000;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('04:59'), findsOneWidget);
      expect(logs.attempts, 1);
      expect(find.byType(PasswordUnlockModal), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  regressionTest(
    'disposal during initialization never creates a session or timer',
    (tester) async {
      final settings = _DelayedMessage();
      final sessions = FakeBlockSessionRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.test',
            settingsRepository: settings,
            blockSessionRepository: sessions,
            blockedAppRepository: FakeBlockedAppRepository(),
            autoOpenModal: false,
          ),
        ),
      );
      final state =
          tester.state(find.byType(LockedScreen)) as WidgetsBindingObserver;
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      settings.firstMessage.complete('Late message');
      await tester.pump(const Duration(seconds: 2));
      expect(sessions.sessions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  regressionTest(
    'successful submission cannot be repeated while the sheet closes',
    (tester) async {
      final channel = _Channel()..nativeSuccess = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => PasswordUnlockModal.show(
                  context,
                  packageName: 'com.test',
                  appId: 1,
                  initialDurationSeconds: 300,
                  settingsRepository: FakeSettingsRepository(
                    expectedPassword: 'secret',
                  ),
                  temporaryUnlockRepository: FakeTemporaryUnlockRepository(),
                  activityLogRepository: FakeActivityLogRepository(),
                  blockedAppRepository: FakeBlockedAppRepository(),
                  platformChannel: channel,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'secret');
      final submit = tester
          .widget<EditableText>(find.byType(EditableText))
          .onSubmitted!;
      submit('secret');
      await tester.pump();
      submit('secret');
      await tester.pumpAndSettle();
      expect(channel.grants, 1);
    },
  );

  regressionTest(
    'native rejection keeps modal open, revokes grant, and preserves session',
    (tester) async {
      final channel = _Channel();
      final unlocks = FakeTemporaryUnlockRepository();
      final logs = FakeActivityLogRepository();
      final sessions = FakeBlockSessionRepository([
        BlockSession(
          id: 1,
          packageName: 'com.test.app',
          startAt: DateTime(2026),
          endAt: DateTime(2026, 1, 2),
          createdAt: DateTime(2026),
          status: BlockSession.statusActive,
        ),
      ]);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await PasswordUnlockModal.show(
                      context,
                      packageName: 'com.test.app',
                      appId: 1,
                      initialDurationSeconds: 300,
                      settingsRepository: FakeSettingsRepository(
                        expectedPassword: 'secret',
                      ),
                      temporaryUnlockRepository: unlocks,
                      activityLogRepository: logs,
                      blockedAppRepository: FakeBlockedAppRepository(),
                      blockSessionRepository: sessions,
                      platformChannel: channel,
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'secret');
      await tester.ensureVisible(find.text('Buka Sementara'));
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(result, isNot(true));
      expect(find.byType(PasswordUnlockModal), findsOneWidget);
      expect(unlocks.unlocks.single.status, TemporaryUnlock.statusRevoked);
      expect(sessions.sessions.single.status, BlockSession.statusActive);
      expect(
        logs.logs.where(
          (log) => log.eventType == ActivityLog.eventTemporaryUnlockStarted,
        ),
        isEmpty,
      );
      expect(channel.revocations, 1);
      expect(find.textContaining('aksesibilitas'), findsOneWidget);
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).isLoading,
        isFalse,
      );
    },
  );

  regressionTest(
    'persistence errors are actionable and clear submission loading',
    (tester) async {
      final channel = _Channel()..nativeSuccess = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              packageName: 'com.test.app',
              appId: 1,
              initialDurationSeconds: 300,
              settingsRepository: FakeSettingsRepository(
                expectedPassword: 'secret',
              ),
              temporaryUnlockRepository: _FailingUnlocks(),
              activityLogRepository: FakeActivityLogRepository(),
              blockedAppRepository: FakeBlockedAppRepository(),
              platformChannel: channel,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'secret');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(channel.grants, 0);
      expect(find.textContaining('menyimpan'), findsOneWidget);
      expect(
        tester.widget<AppButton>(find.byType(AppButton)).isLoading,
        isFalse,
      );
    },
  );

  regressionTest(
    'duplicate keyboard submit verifies once and disposal cancels pending grant',
    (tester) async {
      final settings = _DelayedPassword();
      final unlocks = FakeTemporaryUnlockRepository();
      final channel = _Channel()..nativeSuccess = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              packageName: 'com.test.app',
              appId: 1,
              initialDurationSeconds: 300,
              settingsRepository: settings,
              temporaryUnlockRepository: unlocks,
              activityLogRepository: FakeActivityLogRepository(),
              blockedAppRepository: FakeBlockedAppRepository(),
              platformChannel: channel,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), 'secret');
      final field = tester.widget<EditableText>(find.byType(EditableText));
      field.onSubmitted!('secret');
      field.onSubmitted!('secret');
      expect(settings.attempts, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      settings.verification.complete(true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(unlocks.unlocks, isEmpty);
      expect(channel.grants, 0);
    },
  );

  regressionTest('initialization errors leave loading and offer a safe retry', (
    tester,
  ) async {
    final settings = _FailingSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: LockedScreen(
          packageName: 'com.test.app',
          appName: 'Test app',
          settingsRepository: settings,
          autoOpenModal: false,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(find.text('Buka Kunci Aplikasi'), findsNothing);
    settings.fail = false;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  regressionTest(
    'stale initialization cannot overwrite a new package or create a timer after disposal',
    (tester) async {
      final settings = _DelayedMessage();
      Widget screen(String package, int end) => MaterialApp(
        home: LockedScreen(
          packageName: package,
          appName: package,
          startAtEpochMs: 100000,
          endAtEpochMs: end,
          nowMsProvider: () => 100000,
          settingsRepository: settings,
          autoOpenModal: false,
        ),
      );
      await tester.pumpWidget(screen('com.old', 400000));
      await tester.pumpWidget(screen('com.new', 220000));
      await tester.pump();
      expect(find.text('02:00'), findsOneWidget);
      settings.firstMessage.complete('Stale message');
      await tester.pump();
      expect(find.text('02:00'), findsOneWidget);
      expect(find.text('"Current message"'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );

  regressionTest(
    'failed target launch stays on screen with a retry instead of exiting',
    (tester) async {
      final channel = _Channel()
        ..nativeSuccess = true
        ..launchSuccess = false;
      var unlocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            packageName: 'com.test.app',
            appName: 'Test app',
            appId: 1,
            startAtEpochMs: 100000,
            endAtEpochMs: 100001,
            nowMsProvider: () => 101000,
            settingsRepository: FakeSettingsRepository(
              expectedPassword: 'secret',
            ),
            temporaryUnlockRepository: FakeTemporaryUnlockRepository(),
            activityLogRepository: FakeActivityLogRepository(),
            blockedAppRepository: FakeBlockedAppRepository(),
            platformChannel: channel,
            onUnlocked: () => unlocked = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextFormField), 'secret');
      await tester.ensureVisible(find.text('Buka Sementara'));
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(unlocked, isFalse);
      expect(find.textContaining('membuka aplikasi'), findsOneWidget);
      expect(find.text('Coba Buka Aplikasi Lagi'), findsOneWidget);
      channel.launchSuccess = true;
      await tester.tap(find.text('Coba Buka Aplikasi Lagi'));
      await tester.pump();
      expect(unlocked, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

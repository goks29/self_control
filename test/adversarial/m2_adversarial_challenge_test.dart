import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/data/models/temporary_unlock.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/lock/widgets/session_expired_modal.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  group('Challenge 1: LockedScreen Countdown & Clock Tampering', () {
    testWidgets('Exact countdown formatting for positive remaining duration', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Distracting App',
            packageName: 'com.distract.app',
            startAtEpochMs: now,
            endAtEpochMs: now + 185000, // 3m 5s
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('03:05'), findsOneWidget);
      expect(find.text('Tunggu hingga timer selesai untuk membuka akses'), findsOneWidget);
    });

    testWidgets('Forward jump clamps remaining time to 00:00 without negative values', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Distracting App',
            packageName: 'com.distract.app',
            startAtEpochMs: now - 600000, // 10 minutes ago
            endAtEpochMs: now - 300000,   // 5 minutes ago (elapsed in past)
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('Waktu tunggu telah selesai'), findsOneWidget);
      expect(find.text('Buka Kunci Aplikasi'), findsOneWidget);
      // Ensure no negative countdown strings rendered
      expect(find.textContaining('-'), findsNothing);
    });

    testWidgets('Anti-tampering backward jump clamps to full wait duration', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      // Device clock set to past: now is earlier than startAtEpochMs
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Distracting App',
            packageName: 'com.distract.app',
            startAtEpochMs: now + 60000,  // start is in future compared to now
            endAtEpochMs: now + 360000,   // total wait = 300 seconds (5m)
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should clamp to (360000 - 60000) / 1000 = 300s -> 05:00
      expect(find.text('05:00'), findsOneWidget);
      expect(find.text('Tunggu hingga timer selesai untuk membuka akses'), findsOneWidget);
    });

    testWidgets('Anti-tampering inverted timestamps fallback to safe 300 seconds', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      // Inverted corrupt timestamps: end <= start, now < start
      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Distracting App',
            packageName: 'com.distract.app',
            startAtEpochMs: now + 50000,
            endAtEpochMs: now + 10000, // end is BEFORE start
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // totalSeconds is negative, so fallback to 300s -> 05:00
      expect(find.text('05:00'), findsOneWidget);
    });

    testWidgets('Auto-modal triggers exactly at 00:00 when autoOpenModal is true', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'TikTok',
            packageName: 'com.tiktok.android',
            startAtEpochMs: now - 5000,
            endAtEpochMs: now - 500, // already elapsed -> 00:00
            settingsRepository: settingsRepo,
            autoOpenModal: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('00:00'), findsOneWidget);
      expect(find.byType(PasswordUnlockModal), findsOneWidget);
    });

    testWidgets('autoOpenModal false prevents auto opening and displays unlock button', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'TikTok',
            packageName: 'com.tiktok.android',
            startAtEpochMs: now - 5000,
            endAtEpochMs: now - 1000, // already 00:00
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('00:00'), findsOneWidget);
      expect(find.byType(PasswordUnlockModal), findsNothing);
      expect(find.text('Buka Kunci Aplikasi'), findsOneWidget);

      await tester.tap(find.text('Buka Kunci Aplikasi'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PasswordUnlockModal), findsOneWidget);
    });

    testWidgets('Custom lock message displays italicized in quotation banner', (tester) async {
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'custom_lock_message': 'Fokus adalah kunci kesuksesanmu!',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('"Fokus adalah kunci kesuksesanmu!"'), findsOneWidget);
    });

    testWidgets('Omitted epoch arguments fetch waiting duration from settings', (tester) async {
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'waiting_duration_seconds': '120',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'YouTube',
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('02:00'), findsOneWidget);
    });
  });

  group('Challenge 2: PopScope Invariant & Lock Barrier Non-Bypassability', () {
    testWidgets('System back gesture does not dismiss LockedScreen and invokes SystemNavigator.pop', (tester) async {
      final List<MethodCall> platformCalls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Stack(
                  children: [
                    const Text('Underlying Restricted Application Screen'),
                    LockedScreen(
                      appName: 'Restricted App',
                      autoOpenModal: false,
                      settingsRepository: FakeSettingsRepository(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LockedScreen), findsOneWidget);

      // Simulate system back button / gesture
      final popHandled = await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // handlePopRoute is handled by PopScope
      expect(popHandled, isTrue);
      // LockedScreen is STILL present, NOT dismissed
      expect(find.byType(LockedScreen), findsOneWidget);
      // SystemNavigator.pop was called
      expect(
        platformCalls.any((call) => call.method == 'SystemNavigator.pop'),
        isTrue,
      );
    });

    testWidgets('Kembali ke Layar Utama button triggers SystemNavigator.pop', (tester) async {
      final List<MethodCall> platformCalls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Target App',
            autoOpenModal: false,
            settingsRepository: FakeSettingsRepository(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Kembali ke Layar Utama'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        platformCalls.any((call) => call.method == 'SystemNavigator.pop'),
        isTrue,
      );
      // LockedScreen is still intact
      expect(find.byType(LockedScreen), findsOneWidget);
    });

    testWidgets('Dismissing password modal without unlocking retains LockedScreen barrier', (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Protected App',
            startAtEpochMs: now - 2000,
            endAtEpochMs: now - 1000,
            settingsRepository: settingsRepo,
            autoOpenModal: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PasswordUnlockModal), findsOneWidget);

      // Dismiss bottom sheet via tapping top barrier scrim
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Modal is closed
      expect(find.byType(PasswordUnlockModal), findsNothing);
      // LockedScreen barrier remains active and intact
      expect(find.byType(LockedScreen), findsOneWidget);
      expect(find.text('Protected App'), findsOneWidget);
      expect(find.text('Buka Kunci Aplikasi'), findsOneWidget);
    });
  });

  group('Challenge 3: PasswordUnlockModal Adversarial Stress', () {
    testWidgets('Incorrect password logs password_failed event and prevents unlock', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'correctPassword123');
      final logRepo = FakeActivityLogRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'Twitter',
              packageName: 'com.twitter.android',
              appId: 10,
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
              temporaryUnlockRepository: unlockRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Attempt 1: wrong password
      await tester.enterText(find.byType(TextFormField).first, 'wrong1');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(find.text('Password salah. Silakan coba lagi.'), findsOneWidget);
      expect(logRepo.logs.length, 1);
      expect(logRepo.logs.first.eventType, ActivityLog.eventPasswordFailed);
      expect(logRepo.logs.first.packageNameSnapshot, 'com.twitter.android');
      expect(logRepo.logs.first.appNameSnapshot, 'Twitter');
      expect(logRepo.logs.first.appId, 10);
      expect(unlockRepo.unlocks, isEmpty);

      // Attempt 2: second wrong password
      await tester.enterText(find.byType(TextFormField).first, 'wrong2');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(logRepo.logs.length, 2);
      expect(logRepo.logs[1].eventType, ActivityLog.eventPasswordFailed);
      expect(unlockRepo.unlocks, isEmpty);
    });

    testWidgets('Empty password submission displays error without logging audit event', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'securePassword');
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'Twitter',
              packageName: 'com.twitter.android',
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(find.text('Masukkan password'), findsOneWidget);
      // Empty input should not write spam audit log
      expect(logRepo.logs, isEmpty);
    });

    testWidgets('Duration chips: 5m, 10m, and 15m selection updates unlock duration', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'pass');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'App',
              packageName: 'com.app',
              appId: 1,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Select 15 menit chip
      await tester.tap(find.text('15 menit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'pass');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(unlockRepo.unlocks.length, 1);
      final unlock = unlockRepo.unlocks.first;
      final diffSeconds = unlock.endAt.difference(unlock.startAt).inSeconds;
      expect(diffSeconds, 900); // 15 mins * 60 = 900s
    });

    testWidgets('Custom duration clamp lower bound: 0 minutes clamps to 1 minute (60s)', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'pass');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'App',
              packageName: 'com.app',
              appId: 1,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kustom'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.enterText(find.byType(TextFormField).at(0), 'pass');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump();

      expect(unlockRepo.unlocks.length, 1);
      expect(unlockRepo.unlocks.first.endAt.difference(unlockRepo.unlocks.first.startAt).inSeconds, 60);
    });

    testWidgets('Custom duration clamp upper bound: 999 minutes clamps to 180 minutes (10800s)', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'pass');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'App',
              packageName: 'com.app',
              appId: 1,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kustom'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '999');
      await tester.enterText(find.byType(TextFormField).at(0), 'pass');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump();

      expect(unlockRepo.unlocks.length, 1);
      expect(unlockRepo.unlocks.first.endAt.difference(unlockRepo.unlocks.first.startAt).inSeconds, 10800);
    });

    testWidgets('Custom duration empty input falls back to default 10 minutes (600s)', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'pass');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              appName: 'App',
              packageName: 'com.app',
              appId: 1,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kustom'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.enterText(find.byType(TextFormField).at(0), 'pass');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump();

      expect(unlockRepo.unlocks.length, 1);
      expect(unlockRepo.unlocks.first.endAt.difference(unlockRepo.unlocks.first.startAt).inSeconds, 600);
    });

    testWidgets('Valid unlock resolves appId from BlockedAppRepository when appId is omitted', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'mypassword');
      final logRepo = FakeActivityLogRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();
      final appRepo = FakeBlockedAppRepository([
        BlockedApp(
          id: 55,
          packageName: 'com.reddit.frontpage',
          appName: 'Reddit',
          isSelected: true,
          createdAt: DateTime.now(),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              packageName: 'com.reddit.frontpage',
              appName: 'Reddit',
              appId: null, // Omitted
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
              temporaryUnlockRepository: unlockRepo,
              blockedAppRepository: appRepo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'mypassword');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(unlockRepo.unlocks.length, 1);
      expect(unlockRepo.unlocks.first.appId, 55);
      expect(unlockRepo.unlocks.first.status, TemporaryUnlock.statusActive);

      expect(logRepo.logs.length, 1);
      expect(logRepo.logs.first.eventType, ActivityLog.eventTemporaryUnlockStarted);
      expect(logRepo.logs.first.appId, 55);
      expect(logRepo.logs.first.packageNameSnapshot, 'com.reddit.frontpage');
    });
  });

  group('Challenge 4: SessionExpiredModal Barrier & Lock Re-Engagement', () {
    testWidgets('SessionExpiredModal renders exact Indonesian copy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => SessionExpiredModal.show(context),
                  child: const Text('Show Modal'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionExpiredModal), findsOneWidget);
      expect(find.text('Akses Berakhir'), findsOneWidget);
      expect(
        find.text('Waktu akses sementara telah berakhir. Aplikasi kembali dibatasi.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
      expect(find.text('Kembali'), findsOneWidget);
    });

    testWidgets('SessionExpiredModal is not dismissible by tapping barrier outside dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () => SessionExpiredModal.show(context),
                  child: const Text('Show Modal'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionExpiredModal), findsOneWidget);

      // Tap top-left scrim barrier (outside dialog)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Modal must remain open
      expect(find.byType(SessionExpiredModal), findsOneWidget);
    });

    testWidgets('Dismissing SessionExpiredModal via Kembali button cleanly re-engages LockedScreen', (tester) async {
      final List<MethodCall> platformCalls = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call);
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Stack(
                children: [
                  LockedScreen(
                    appName: 'Restricted App',
                    autoOpenModal: false,
                    settingsRepository: FakeSettingsRepository(),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: ElevatedButton(
                      onPressed: () => SessionExpiredModal.show(context),
                      child: const Text('Trigger Expired Alert'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Trigger session expired dialog
      await tester.tap(find.text('Trigger Expired Alert'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SessionExpiredModal), findsOneWidget);

      // Dismiss dialog via 'Kembali'
      await tester.tap(find.text('Kembali'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog is gone
      expect(find.byType(SessionExpiredModal), findsNothing);

      // Underlying LockedScreen is re-engaged and fully present
      expect(find.byType(LockedScreen), findsOneWidget);
      expect(find.text('Restricted App'), findsOneWidget);
      expect(find.text('Aplikasi ini sedang dibatasi'), findsOneWidget);

      // Verify PopScope back barrier invariant is still strictly enforced
      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(handled, isTrue);
      expect(find.byType(LockedScreen), findsOneWidget);
      expect(
        platformCalls.any((call) => call.method == 'SystemNavigator.pop'),
        isTrue,
      );
    });
  });
}

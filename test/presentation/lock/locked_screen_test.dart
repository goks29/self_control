import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/focus_task.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('LockedScreen Tests', () {
    testWidgets('renders app name, custom message, and countdown timer', (tester) async {
      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'custom_lock_message': 'Ingat impian besarmu.',
          'waiting_duration_seconds': '300',
        },
      );
      final now = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            packageName: 'com.instagram.android',
            startAtEpochMs: now,
            endAtEpochMs: now + 300000,
            settingsRepository: settingsRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('Aplikasi ini sedang dibatasi'), findsOneWidget);
      expect(find.text('"Ingat impian besarmu."'), findsOneWidget);
      expect(find.text('05:00'), findsOneWidget);
      expect(find.byIcon(Icons.hourglass_bottom_rounded), findsOneWidget);
    });

    testWidgets('auto-triggers password modal when countdown reaches 00:00', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      final now = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'TikTok',
            packageName: 'com.tiktok.android',
            startAtEpochMs: now - 10000,
            endAtEpochMs: now - 1000,
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

    testWidgets('launches target app and triggers onUnlocked when password unlock succeeds', (tester) async {
      final settingsRepo = FakeSettingsRepository(expectedPassword: 'correct123');
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final platformChannel = FakeBlockingPlatformChannel();
      final now = DateTime.now().millisecondsSinceEpoch;
      var onUnlockedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'TikTok',
            packageName: 'com.tiktok.android',
            appId: 1,
            startAtEpochMs: now - 10000,
            endAtEpochMs: now - 1000,
            settingsRepository: settingsRepo,
            temporaryUnlockRepository: unlockRepo,
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            platformChannel: platformChannel,
            autoOpenModal: true,
            onUnlocked: () {
              onUnlockedCalled = true;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PasswordUnlockModal), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'correct123');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));

      expect(platformChannel.lastLaunchedTargetApp, 'com.tiktok.android');
      expect(onUnlockedCalled, isTrue);
    });

    testWidgets('returns to home screen when Kembali ke Layar Utama is tapped', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LockedScreen(
                      appName: 'Instagram',
                      packageName: 'com.instagram.android',
                      startAtEpochMs: DateTime.now().millisecondsSinceEpoch,
                      endAtEpochMs: DateTime.now().millisecondsSinceEpoch + 300000,
                      settingsRepository: settingsRepo,
                      autoOpenModal: false,
                    ),
                  ),
                ).then((_) => popped = true);
              },
              child: const Text('Open Lock'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Lock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Kembali ke Layar Utama'), findsOneWidget);
      await tester.tap(find.text('Kembali ke Layar Utama'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(popped, isTrue);
      expect(find.text('Open Lock'), findsOneWidget);
    });

    testWidgets('renders pending focus tasks and allows toggling from lock screen', (tester) async {
      final settingsRepo = FakeSettingsRepository();
      final taskRepo = FakeTaskRepository([
        FocusTask(
          id: 1,
          title: 'Selesaikan Tugas Kuliah',
          isCompleted: false,
          createdAt: DateTime.now(),
        ),
      ]);
      final now = DateTime.now().millisecondsSinceEpoch;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            packageName: 'com.instagram.android',
            startAtEpochMs: now,
            endAtEpochMs: now + 300000,
            settingsRepository: settingsRepo,
            taskRepository: taskRepo,
            autoOpenModal: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tugas yang Harus Dikerjakan:'), findsOneWidget);
      expect(find.text('Selesaikan Tugas Kuliah'), findsOneWidget);

      await tester.tap(find.text('Selesaikan Tugas Kuliah'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Tugas yang Harus Dikerjakan:'), findsNothing);
      expect((await taskRepo.getAllTasks()).first.isCompleted, isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/presentation/home/dashboard_screen.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('DashboardScreen Tests', () {
    testWidgets('displays empty state when no activity logs exist', (tester) async {
      final logRepo = FakeActivityLogRepository();
      bool navigated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            activityLogRepository: logRepo,
            onNavigateToApplications: () => navigated = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Belum Ada Aktivitas Blokir'), findsOneWidget);
      expect(
        find.text(
          'Belum ada aktivitas percobaan membuka aplikasi. Pilih aplikasi yang ingin dibatasi di tab Aplikasi untuk mulai melindungi fokus Anda.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pilih Aplikasi'), findsOneWidget);

      await tester.tap(find.text('Pilih Aplikasi'));
      await tester.pump();
      expect(navigated, isTrue);
    });

    testWidgets('displays metric card and intercepted app list when logs exist', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final now = DateTime.now();

      await logRepo.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.instagram.android',
          appNameSnapshot: 'Instagram',
          eventType: ActivityLog.eventBlockedAttempt,
          attemptedAt: now.subtract(const Duration(minutes: 5)),
        ),
      );
      await logRepo.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.instagram.android',
          appNameSnapshot: 'Instagram',
          eventType: ActivityLog.eventBlockedAttempt,
          attemptedAt: now.subtract(const Duration(minutes: 2)),
        ),
      );
      await logRepo.logEvent(
        ActivityLog(
          packageNameSnapshot: 'com.tiktok.android',
          appNameSnapshot: 'TikTok',
          eventType: ActivityLog.eventBlockedAttempt,
          attemptedAt: now.subtract(const Duration(minutes: 1)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            activityLogRepository: logRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total Percobaan Dicegah'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Aplikasi Terbanyak Diblokir'), findsOneWidget);
      expect(find.text('2 aplikasi'), findsOneWidget);
      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('2 kali'), findsOneWidget);
      expect(find.text('1 kali'), findsOneWidget);
    });

    testWidgets('allows adding, editing via tap, toggling, and deleting tasks', (tester) async {
      final logRepo = FakeActivityLogRepository();
      final taskRepo = FakeTaskRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            activityLogRepository: logRepo,
            taskRepository: taskRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Daftar Tugas Fokus'), findsOneWidget);
      expect(find.text('0 belum selesai'), findsOneWidget);

      // Add task
      await tester.enterText(
        find.widgetWithText(TextField, 'Tambah tugas yang harus dikerjakan...'),
        'Belajar Matematika',
      );
      await tester.tap(find.text('Tambah'));
      await tester.pumpAndSettle();

      expect(find.text('Belajar Matematika'), findsOneWidget);
      expect(find.text('1 belum selesai'), findsOneWidget);

      // Tap task to edit
      await tester.tap(find.text('Belajar Matematika'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Tugas'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Belajar Matematika'),
        'Belajar Fisika',
      );
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(find.text('Belajar Fisika'), findsOneWidget);
      expect(find.text('Belajar Matematika'), findsNothing);

      // Toggle task
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('0 belum selesai'), findsOneWidget);

      // Delete task
      await tester.tap(find.byTooltip('Hapus Tugas'));
      await tester.pumpAndSettle();
      expect(find.text('Belajar Fisika'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/settings/settings_screen.dart';
import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('SettingsScreen Tests', () {
    testWidgets('loads existing settings and updates values on save', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsRepo = FakeSettingsRepository(
        initialSettings: {
          'waiting_duration_seconds': '300',
          'custom_lock_message': 'Tetap produktif hari ini.',
          'default_unlock_duration_seconds': '600',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsRepository: settingsRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan'), findsOneWidget);
      expect(find.text('5 menit'), findsWidgets);
      expect(find.text('Tetap produktif hari ini.'), findsOneWidget);

      await tester.tap(find.text('10 menit').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tetap produktif hari ini.'),
        'Fokus masa depan.',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Pengaturan berhasil disimpan.'), findsOneWidget);
      final savedDuration = await settingsRepo.getWaitingDurationSeconds();
      final savedMessage = await settingsRepo.getCustomLockMessage();
      expect(savedDuration, 600);
      expect(savedMessage, 'Fokus masa depan.');
    });

    testWidgets('validates password mismatch and length', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsRepo = FakeSettingsRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsRepository: settingsRepo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(1), '123');
      await tester.enterText(textFields.at(2), '123');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Password minimal 4 karakter'), findsOneWidget);

      await tester.enterText(textFields.at(1), '12345');
      await tester.enterText(textFields.at(2), '54321');
      await tester.tap(find.text('Simpan Pengaturan'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi password tidak cocok'), findsOneWidget);
    });

    testWidgets('shows integrity check and emergency reset dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsRepo = FakeSettingsRepository();
      final fakeDb = FakeAppDatabase();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settingsRepository: settingsRepo,
            appDatabase: fakeDb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pemulihan & Integritas Data'), findsOneWidget);
      expect(find.text('Cek Integritas'), findsOneWidget);
      expect(find.text('Reset Darurat'), findsOneWidget);

      await tester.tap(find.text('Cek Integritas'));
      await tester.pump();

      expect(fakeDb.verifyIntegrityCalled, isTrue);
      expect(find.text('Basis data sehat. Tidak ditemukan kerusakan atau pelanggaran relasi.'), findsOneWidget);

      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Reset'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(find.text('Konfirmasi Reset'), findsNothing);
      expect(fakeDb.resetToDefaultsCalled, isFalse);

      await tester.tap(find.text('Reset Darurat'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(fakeDb.resetToDefaultsCalled, isTrue);
      expect(find.text('Seluruh pengaturan dan data berhasil direset.'), findsOneWidget);
    });
  });
}

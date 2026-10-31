import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/presentation/application/application_selection_screen.dart';
import 'package:self_control/presentation/application/widgets/permission_guide_modal.dart';

import '../test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('ApplicationSelectionScreen Tests', () {
    testWidgets('renders app list with checkboxes and updates selection', (
      tester,
    ) async {
      final now = DateTime.now();
      final appRepo = FakeBlockedAppRepository([
        BlockedApp(
          id: 1,
          packageName: 'com.instagram.android',
          appName: 'Instagram',
          isSelected: false,
          createdAt: now,
        ),
        BlockedApp(
          id: 2,
          packageName: 'com.tiktok.android',
          appName: 'TikTok',
          isSelected: true,
          createdAt: now,
        ),
      ]);
      final platform = FakeBlockingPlatformChannel(
        accessibilityStatus: 'enabled',
        installedApps: appRepo.apps
            .map(
              (app) => <String, dynamic>{
                'packageName': app.packageName,
                'appName': app.appName,
              },
            )
            .toList(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: appRepo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('TikTok'), findsOneWidget);
      expect(find.text('1 aplikasi dipilih'), findsOneWidget);

      await tester.tap(find.text('Instagram'));
      await tester.pumpAndSettle();

      expect(find.text('2 aplikasi dipilih'), findsOneWidget);
      final updatedApp = await appRepo.getAppByPackageName(
        'com.instagram.android',
      );
      expect(updatedApp?.isSelected, isTrue);
    });

    testWidgets('search filters app list', (tester) async {
      final now = DateTime.now();
      final appRepo = FakeBlockedAppRepository([
        BlockedApp(
          packageName: 'com.instagram.android',
          appName: 'Instagram',
          isSelected: false,
          createdAt: now,
        ),
        BlockedApp(
          packageName: 'com.twitter.android',
          appName: 'X / Twitter',
          isSelected: false,
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: appRepo,
            platformChannel: FakeBlockingPlatformChannel(
              installedApps: appRepo.apps
                  .map(
                    (app) => <String, dynamic>{
                      'packageName': app.packageName,
                      'appName': app.appName,
                    },
                  )
                  .toList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'insta');
      await tester.pumpAndSettle();

      expect(find.text('Instagram'), findsOneWidget);
      expect(find.text('X / Twitter'), findsNothing);
    });

    testWidgets(
      'triggers PermissionGuideModal when accessibility is disabled',
      (tester) async {
        final appRepo = FakeBlockedAppRepository();
        final platform = FakeBlockingPlatformChannel(
          accessibilityStatus: 'disabled',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ApplicationSelectionScreen(
              blockedAppRepository: appRepo,
              platformChannel: platform,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Aktifkan Pemblokiran'));
        await tester.pumpAndSettle();

        expect(find.byType(PermissionGuideModal), findsOneWidget);
        expect(find.text('Aktivasi Layanan Aksesibilitas'), findsOneWidget);
      },
    );
  });
}

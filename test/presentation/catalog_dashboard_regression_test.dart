import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/presentation/application/application_selection_screen.dart';
import 'package:self_control/presentation/home/dashboard_screen.dart';

import 'test_helpers.dart';

BlockedApp app(String package, {bool selected = false}) => BlockedApp(
  id: package == 'old' ? 1 : 2,
  packageName: package,
  appName: package,
  isSelected: selected,
  createdAt: DateTime(2025),
);

class CatalogPlatform extends FakeBlockingPlatformChannel {
  CatalogPlatform() : super(accessibilityStatus: 'enabled');
  bool fail = false;
  Map<String, dynamic>? syncResult;
  Completer<void>? syncGate;
  int syncCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (fail) throw StateError('native unavailable');
    return installedApps;
  }

  @override
  Future<Map<String, dynamic>> syncBlockedApps(List<String> packages) async {
    syncCalls++;
    if (syncGate != null) await syncGate!.future;
    return syncResult ?? super.syncBlockedApps(packages);
  }
}

class SelectionRepository extends FakeBlockedAppRepository {
  SelectionRepository(super.apps);
  bool fail = false;
  Completer<void>? gate;
  int activeWrites = 0;
  int maxWrites = 0;
  int writes = 0;
  int? failOnWrite;

  @override
  Future<void> setAppSelected(String packageName, bool isSelected) async {
    activeWrites++;
    if (activeWrites > maxWrites) maxWrites = activeWrites;
    try {
      if (gate != null) await gate!.future;
      writes++;
      if (fail || writes == failOnWrite) throw StateError('write failed');
      await super.setAppSelected(packageName, isSelected);
    } finally {
      activeWrites--;
    }
  }
}

class FailingCatalogRepository extends FakeBlockedAppRepository {
  bool fail = true;

  @override
  Future<List<BlockedApp>> getAllApps() async {
    if (fail) throw StateError('database unavailable');
    return super.getAllApps();
  }
}

class DashboardRepository extends FakeActivityLogRepository {
  bool fail = false;
  final List<Completer<Map<String, int>>> requests = [];
  bool delay = false;

  @override
  Future<Map<String, int>> getAttemptCountsByPackage({
    String? outcome = ActivityLog.outcomeConfirmed,
  }) async {
    if (fail) throw StateError('database unavailable');
    if (!delay) return {'fresh': 3};
    final request = Completer<Map<String, int>>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  setUpAll(setupTestFonts);

  testWidgets('catalog database failure ends loading and allows retry', (
    tester,
  ) async {
    final repo = FailingCatalogRepository();
    final platform = CatalogPlatform();
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: repo,
          platformChannel: platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gagal memuat daftar aplikasi.'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Gagal memuat daftar aplikasi.'), findsNothing);
    expect(find.text('Tidak ada aplikasi terpasang'), findsOneWidget);
  });

  testWidgets('partial select-all failure reflects only committed writes', (
    tester,
  ) async {
    final repo = SelectionRepository([app('a'), app('b')])..failOnWrite = 2;
    final platform = CatalogPlatform()
      ..installedApps = [
        {'packageName': 'a', 'appName': 'A'},
        {'packageName': 'b', 'appName': 'B'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: repo,
          platformChannel: platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pilih Semua'));
    await tester.pumpAndSettle();
    expect(find.text('1 aplikasi dipilih'), findsOneWidget);
    expect(find.textContaining('Gagal menyimpan'), findsOneWidget);
    expect((await repo.getSelectedApps()).map((app) => app.packageName), ['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reconciles nonempty catalog without deleting historical rows', (
    tester,
  ) async {
    final repo = FakeBlockedAppRepository([
      app('old'),
      app('kept', selected: true),
    ]);
    final platform = CatalogPlatform()
      ..installedApps = [
        {'packageName': 'kept', 'appName': 'Renamed'},
        {'packageName': 'new', 'appName': 'New'},
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: repo,
          platformChannel: platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('1 aplikasi dipilih'), findsOneWidget);
    expect((await repo.getAppByPackageName('old'))?.id, 1);
    expect((await repo.getAppByPackageName('kept'))?.isSelected, isTrue);
  });

  testWidgets(
    'native failure retains persisted list with retry; empty success hides it',
    (tester) async {
      final repo = FakeBlockedAppRepository([app('old')]);
      final platform = CatalogPlatform()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: repo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old'), findsWidgets);
      expect(find.text('Coba Lagi'), findsOneWidget);
      platform.fail = false;
      await tester.tap(find.text('Coba Lagi'));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsNothing);
      expect(find.text('Tidak ada aplikasi terpasang'), findsOneWidget);
      expect(repo.apps, hasLength(1));
    },
  );

  for (final result in [
    {'status': 'error', 'syncedCount': 1},
    {'status': 'success', 'syncedCount': 0},
  ]) {
    testWidgets('activation rejects invalid acknowledgement $result', (
      tester,
    ) async {
      final platform = CatalogPlatform()
        ..installedApps = [
          {'packageName': 'kept', 'appName': 'Kept'},
        ]
        ..syncResult = result;
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: FakeBlockedAppRepository([
              app('kept', selected: true),
            ]),
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aktifkan Pemblokiran'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Pemblokiran aktif untuk'), findsNothing);
      expect(find.textContaining('Gagal mengaktifkan'), findsOneWidget);
    });
  }

  testWidgets(
    'selection failure restores persisted selection and exposes error',
    (tester) async {
      final repo = SelectionRepository([app('kept')])..fail = true;
      final platform = CatalogPlatform()
        ..installedApps = [
          {'packageName': 'kept', 'appName': 'Kept'},
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: repo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kept'));
      await tester.pumpAndSettle();
      expect(find.text('0 aplikasi dipilih'), findsOneWidget);
      expect(find.textContaining('Gagal menyimpan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'catalog revision reloads installed apps and explicit refresh works',
    (tester) async {
      final repo = FakeBlockedAppRepository([app('kept', selected: true)]);
      final platform = CatalogPlatform()
        ..installedApps = [
          {'packageName': 'kept', 'appName': 'Kept'},
        ];
      Widget screen(int revision) => MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: repo,
          platformChannel: platform,
          refreshRevision: revision,
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      platform.installedApps = [
        {'packageName': 'new', 'appName': 'New'},
      ];
      await tester.pumpWidget(screen(1));
      await tester.pumpAndSettle();
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Kept'), findsNothing);
      platform.installedApps = [];
      await tester.tap(find.byTooltip('Segarkan aplikasi'));
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada aplikasi terpasang'), findsOneWidget);
      expect((await repo.getAppByPackageName('kept'))!.isSelected, isTrue);
    },
  );

  testWidgets(
    'selection writes cannot overlap or race activation and refresh',
    (tester) async {
      final gate = Completer<void>();
      final repo = SelectionRepository([app('kept')])..gate = gate;
      final platform = CatalogPlatform()
        ..installedApps = [
          {'packageName': 'kept', 'appName': 'Kept'},
        ];
      Widget screen(int revision) => MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: repo,
          platformChannel: platform,
          refreshRevision: revision,
        ),
      );
      await tester.pumpWidget(screen(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kept'));
      await tester.tap(find.text('Kept'));
      await tester.tap(find.text('Aktifkan Pemblokiran'));
      await tester.pumpWidget(screen(1));
      await tester.pump();
      expect(repo.maxWrites, 1);
      expect(platform.syncCalls, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('1 aplikasi dipilih'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission guide settles while duplicate activation stays guarded',
    (tester) async {
      final platform = CatalogPlatform()..accessibilityStatus = 'disabled';
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: FakeBlockedAppRepository(),
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aktifkan Pemblokiran'));
      await tester.pumpAndSettle();
      expect(find.text('Aktivasi Layanan Aksesibilitas'), findsOneWidget);
      expect(platform.syncCalls, 0);
    },
  );

  testWidgets('activation remains busy until native sync completes', (
    tester,
  ) async {
    final gate = Completer<void>();
    final platform = CatalogPlatform()..syncGate = gate;
    await tester.pumpWidget(
      MaterialApp(
        home: ApplicationSelectionScreen(
          blockedAppRepository: FakeBlockedAppRepository(),
          platformChannel: platform,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aktifkan Pemblokiran'));
    await tester.tap(find.text('Aktifkan Pemblokiran'));
    await tester.pump();
    expect(platform.syncCalls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Pemblokiran aktif untuk 0 aplikasi'), findsOneWidget);
  });

  testWidgets('dashboard revision ignores stale success and stale failure', (
    tester,
  ) async {
    final repo = DashboardRepository()..delay = true;
    Widget screen(int revision) => MaterialApp(
      home: DashboardScreen(
        activityLogRepository: repo,
        refreshRevision: revision,
      ),
    );
    await tester.pumpWidget(screen(0));
    await tester.pump();
    await tester.pumpWidget(screen(1));
    await tester.pump();
    repo.requests[1].complete({'new': 7});
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    repo.requests[0].complete({'stale': 99});
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    await tester.pumpWidget(screen(2));
    await tester.pump();
    await tester.pumpWidget(screen(3));
    await tester.pump();
    repo.requests[3].complete({'latest': 8});
    await tester.pumpAndSettle();
    repo.requests[2].completeError(StateError('stale error'));
    await tester.pumpAndSettle();
    expect(find.text('8'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'async selection and dashboard completion after disposal is safe',
    (tester) async {
      final gate = Completer<void>();
      final repo = SelectionRepository([app('kept')])..gate = gate;
      final platform = CatalogPlatform()
        ..installedApps = [
          {'packageName': 'kept', 'appName': 'Kept'},
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: ApplicationSelectionScreen(
            blockedAppRepository: repo,
            platformChannel: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kept'));
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final logs = DashboardRepository()..delay = true;
      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(activityLogRepository: logs)),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      logs.requests.single.completeError(StateError('disposed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard failure offers working retry', (tester) async {
    final repo = DashboardRepository()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: DashboardScreen(activityLogRepository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coba Lagi'), findsOneWidget);
    repo.fail = false;
    await tester.tap(find.text('Coba Lagi'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

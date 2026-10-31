import 'dart:developer' as developer;

import '../../core/platform/blocking_platform_channel.dart';
import '../../data/models/blocked_app.dart';
import '../../data/repositories/blocked_app_repository.dart';

class ApplicationCatalogResult {
  const ApplicationCatalogResult(this.apps, {this.error});

  final List<BlockedApp> apps;
  final Object? error;
}

class ApplicationCatalogService {
  ApplicationCatalogService({
    required this.repository,
    required this.platformChannel,
  });

  final BlockedAppRepository repository;
  final BlockingPlatformChannel platformChannel;

  Future<ApplicationCatalogResult> loadApps() async {
    final persisted = await repository.getAllApps();
    final byPackage = {for (final app in persisted) app.packageName: app};
    try {
      // Only a successful native response (including []) is authoritative.
      final installed = await platformChannel.getInstalledApps();
      final current = <String, BlockedApp>{};
      for (final app in installed) {
        final package = app['packageName'] as String;
        final name = app['appName'] as String;
        current[package] =
            byPackage[package]?.copyWith(appName: name) ??
            BlockedApp(
              packageName: package,
              appName: name,
              isSelected: false,
              createdAt: DateTime.now(),
            );
      }
      // Upsert, never delete: historical logs/sessions still reference old rows.
      await repository.saveApps(current.values.toList());
      final saved = await repository.getAllApps();
      return ApplicationCatalogResult(
        _sorted(saved.where((app) => current.containsKey(app.packageName))),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Catalog reconciliation failed; retaining persisted apps',
        name: 'ApplicationCatalogService.loadApps',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return ApplicationCatalogResult(_sorted(persisted), error: error);
    }
  }

  /// Returns false when accessibility permission must be granted first.
  Future<bool> activateBlocking(List<BlockedApp> apps) async {
    if (await platformChannel.getAccessibilityStatus() != 'enabled') {
      return false;
    }
    final packages = apps
        .where((app) => app.isSelected)
        .map((app) => app.packageName)
        .toSet()
        .toList();
    final result = await platformChannel.syncBlockedApps(packages);
    if (result['status'] != 'success' ||
        result['syncedCount'] != packages.length) {
      throw StateError(
        'Native blocking synchronization was not acknowledged: '
        'status=${result['status']}, syncedCount=${result['syncedCount']}, '
        'expectedCount=${packages.length}',
      );
    }
    return true;
  }

  List<BlockedApp> _sorted(Iterable<BlockedApp> apps) => apps.toList()
    ..sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
}

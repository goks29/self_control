@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/database_maintenance_service.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/core/platform/database_files.dart';
import 'package:self_control/data/database/app_database.dart';

void main() {
  test(
    'database maintenance imports compile on web without IO file access',
    () {
      final database = AppDatabase();
      final service = DatabaseMaintenanceService(
        database: database,
        channel: BlockingPlatformChannel(),
      );
      expect(service.database.recoveredOnOpen, isFalse);
      expect(
        () => backupCorruptFiles('database.db', 1),
        throwsUnsupportedError,
      );
    },
  );
}

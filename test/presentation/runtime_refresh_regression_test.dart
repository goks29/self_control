import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';

import 'test_helpers.dart';

class RetryLogRepository extends FakeActivityLogRepository {
  bool fail = true;
  @override
  Future<void> logEvent(dynamic log) async {
    if (fail) throw StateError('database busy');
    await super.logEvent(log);
  }
}

void main() {
  setUpAll(setupTestFonts);

  testWidgets('dashboard refreshes after pending native logs are imported', (
    tester,
  ) async {
    final channel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');
    channel.pendingActivityLogs = [
      {
        'packageName': 'app.target',
        'outcome': 'confirmed',
        'timestampMs': 1700000000000,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MainScaffold(
          platformChannel: channel,
          activityLogRepository: FakeActivityLogRepository(),
          blockedAppRepository: FakeBlockedAppRepository(),
          temporaryUnlockRepository: FakeTemporaryUnlockRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total Percobaan Dicegah'), findsOneWidget);
    expect(find.text('1 kali'), findsOneWidget);
  });

  testWidgets('failed imported logs are retained for an explicit retry', (
    tester,
  ) async {
    final repository = RetryLogRepository();
    final channel = FakeBlockingPlatformChannel(accessibilityStatus: 'enabled');
    channel.pendingActivityLogs = [
      {
        'packageName': 'app.target',
        'outcome': 'confirmed',
        'timestampMs': 1700000000000,
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: MainScaffold(
          platformChannel: channel,
          activityLogRepository: repository,
          blockedAppRepository: FakeBlockedAppRepository(),
          temporaryUnlockRepository: FakeTemporaryUnlockRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.logs, isEmpty);
    expect(find.text('Coba Lagi'), findsWidgets);
    repository.fail = false;
    await tester.tap(find.text('Coba Lagi').first);
    await tester.pumpAndSettle();
    expect(repository.logs, hasLength(1));
    expect(find.text('Total Percobaan Dicegah'), findsOneWidget);
  });
}

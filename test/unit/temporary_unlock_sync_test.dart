import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import '../presentation/test_helpers.dart';

void main() {
  setUpAll(() {
    setupTestFonts();
  });

  group('Temporary Unlock Platform Channel Synchronization Tests', () {
    test('syncTemporaryUnlock dispatches correct arguments across channel', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'syncTemporaryUnlock') {
            return {'status': 'success', 'packageName': call.arguments['packageName']};
          }
          return null;
        },
      );

      final channel = BlockingPlatformChannel();
      final success = await channel.syncTemporaryUnlock(
        packageName: 'com.instagram.android',
        durationSeconds: 600,
        expiresAtEpochMs: 1700000600000,
      );

      expect(success, isTrue);
      expect(calls.length, 1);
      expect(calls.first.method, 'syncTemporaryUnlock');
      expect(calls.first.arguments['packageName'], 'com.instagram.android');
      expect(calls.first.arguments['durationSeconds'], 600);
      expect(calls.first.arguments['expiresAtEpochMs'], 1700000600000);
    });

    test('revokeTemporaryUnlock dispatches correct package name across channel', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'revokeTemporaryUnlock') {
            return {'status': 'success', 'packageName': call.arguments['packageName']};
          }
          return null;
        },
      );

      final channel = BlockingPlatformChannel();
      final success = await channel.revokeTemporaryUnlock('com.tiktok.android');

      expect(success, isTrue);
      expect(calls.length, 1);
      expect(calls.first.method, 'revokeTemporaryUnlock');
      expect(calls.first.arguments['packageName'], 'com.tiktok.android');
    });

    test('syncActiveSessions dispatches strict session and schedule parameters', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'syncActiveSessions') {
            return {'status': 'success'};
          }
          return null;
        },
      );

      final channel = BlockingPlatformChannel();
      final success = await channel.syncActiveSessions(
        isStrictSessionActive: true,
        sessionEndEpochMs: 1800000000000,
        activeSchedule: {
          'scheduleStartMinute': 540,
          'scheduleEndMinute': 1020,
          'daysMask': 127,
          'isEnabled': true,
        },
      );

      expect(success, isTrue);
      expect(calls.length, 1);
      expect(calls.first.method, 'syncActiveSessions');
      expect(calls.first.arguments['isStrictSessionActive'], isTrue);
      expect(calls.first.arguments['sessionEndEpochMs'], 1800000000000);
      expect(calls.first.arguments['activeSchedule']['scheduleStartMinute'], 540);
    });

    test('consumePendingBootEvents drains timestamps from platform', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          if (call.method == 'consumePendingBootEvents') {
            return <int>[1700000000000, 1700000050000];
          }
          return null;
        },
      );

      final channel = BlockingPlatformChannel();
      final events = await channel.consumePendingBootEvents();

      expect(events, [1700000000000, 1700000050000]);
    });

    testWidgets('PasswordUnlockModal invokes syncTemporaryUnlock upon password confirmation', (tester) async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          calls.add(call);
          if (call.method == 'syncTemporaryUnlock') {
            return {'status': 'success'};
          }
          return null;
        },
      );

      final settingsRepo = FakeSettingsRepository(expectedPassword: 'secret');
      final logRepo = FakeActivityLogRepository();
      final unlockRepo = FakeTemporaryUnlockRepository();
      final appRepo = FakeBlockedAppRepository([
        BlockedApp(
          id: 10,
          packageName: 'com.twitter.android',
          appName: 'Twitter',
          isSelected: true,
          createdAt: DateTime.now(),
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PasswordUnlockModal(
              packageName: 'com.twitter.android',
              appName: 'Twitter',
              appId: 10,
              settingsRepository: settingsRepo,
              activityLogRepository: logRepo,
              temporaryUnlockRepository: unlockRepo,
              blockedAppRepository: appRepo,
              initialDurationSeconds: 300,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'secret');
      await tester.tap(find.text('Buka Sementara'));
      await tester.pumpAndSettle();

      expect(unlockRepo.unlocks.length, 1);
      final syncCall = calls.firstWhere((c) => c.method == 'syncTemporaryUnlock');
      expect(syncCall.arguments['packageName'], 'com.twitter.android');
      expect(syncCall.arguments['durationSeconds'], 300);
    });
  });
}

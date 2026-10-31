import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';
import 'package:self_control/data/models/activity_log.dart';
import 'package:self_control/data/models/blocked_app.dart';
import 'package:self_control/main.dart';
import 'package:self_control/presentation/lock/locked_screen.dart';
import 'package:self_control/presentation/lock/widgets/password_unlock_modal.dart';
import 'package:self_control/presentation/navigation/main_scaffold.dart';

import '../presentation/test_helpers.dart';

class _RecordingUnlockChannel extends FakeBlockingPlatformChannel {
  int grantAttempts = 0;

  @override
  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async {
    grantAttempts++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    setupTestFonts();
  });

  group('BlockingPlatformChannel Method & Listener Empirical Challenges', () {
    late BlockingPlatformChannel channel;
    late List<MethodCall> channelLog;

    setUp(() {
      channelLog = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(BlockingPlatformChannel.channelName),
            (MethodCall call) async {
              channelLog.add(call);
              switch (call.method) {
                case 'launchTargetApp':
                  final pkg = call.arguments['packageName'] as String?;
                  if (pkg == 'throw.error.package') {
                    throw PlatformException(
                      code: 'LAUNCH_FAILED',
                      message: 'Activity not found',
                    );
                  }
                  return pkg != null && pkg.isNotEmpty;
                case 'getInitialLockIntent':
                  return {
                    'packageName': 'com.initial.app',
                    'blockedAt': 1700000000000,
                  };
                default:
                  return null;
              }
            },
          );
      channel = BlockingPlatformChannel();
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(BlockingPlatformChannel.channelName),
            null,
          );
    });

    test('registerLockRequestListener prevents duplicate registration of identical callback', () async {
      int invokeCount = 0;
      void listener(String pkg, int blockedAt) {
        invokeCount++;
      }

      channel.registerLockRequestListener(listener);
      channel.registerLockRequestListener(listener);
      channel.registerLockRequestListener(listener);

      final message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'com.test.app',
          'blockedAt': 1710000000000,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BlockingPlatformChannel.channelName,
            message,
            (ByteData? reply) {},
          );

      expect(invokeCount, equals(1));
    });

    test('multiple listeners receive broadcast and unregistering one leaves others intact', () async {
      String? pkg1;
      String? pkg2;
      void listener1(String pkg, int blockedAt) => pkg1 = pkg;
      void listener2(String pkg, int blockedAt) => pkg2 = pkg;

      channel.registerLockRequestListener(listener1);
      channel.registerLockRequestListener(listener2);

      final message1 = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'com.test.one',
          'blockedAt': 1710000000000,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BlockingPlatformChannel.channelName,
            message1,
            (ByteData? reply) {},
          );

      expect(pkg1, equals('com.test.one'));
      expect(pkg2, equals('com.test.one'));

      channel.unregisterLockRequestListener(listener1);

      final message2 = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'com.test.two',
          'blockedAt': 1710000000000,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BlockingPlatformChannel.channelName,
            message2,
            (ByteData? reply) {},
          );

      expect(pkg1, equals('com.test.one'));
      expect(pkg2, equals('com.test.two'));
    });

    test('listener unregistering itself during execution does not throw ConcurrentModificationError', () async {
      int calls = 0;
      late void Function(String, int) selfUnregisteringListener;
      selfUnregisteringListener = (String pkg, int blockedAt) {
        calls++;
        channel.unregisterLockRequestListener(selfUnregisteringListener);
      };

      channel.registerLockRequestListener(selfUnregisteringListener);

      final message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'com.test.self_unregister',
          'blockedAt': 1710000000000,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BlockingPlatformChannel.channelName,
            message,
            (ByteData? reply) {},
          );

      expect(calls, equals(1));

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BlockingPlatformChannel.channelName,
            message,
            (ByteData? reply) {},
          );

      expect(calls, equals(1));
    });

    test('unregistering non-registered listener is a safe no-op', () {
      expect(
        () => channel.unregisterLockRequestListener((pkg, at) {}),
        returnsNormally,
      );
    });

    test(
      'malformed arguments in onLockRequested are parsed with safe defaults',
      () async {
        String? parsedPkg;
        int? parsedBlockedAt;
        channel.registerLockRequestListener((pkg, at) {
          parsedPkg = pkg;
          parsedBlockedAt = at;
        });

        final emptyMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onLockRequested', null),
        );

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              BlockingPlatformChannel.channelName,
              emptyMessage,
              (ByteData? reply) {},
            );

        expect(parsedPkg, equals(''));
        expect(parsedBlockedAt, isNotNull);

        final doubleMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onLockRequested', {
            'packageName': 'com.double.time',
            'blockedAt': 1720000000000.95,
          }),
        );

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              BlockingPlatformChannel.channelName,
              doubleMessage,
              (ByteData? reply) {},
            );

        expect(parsedPkg, equals('com.double.time'));
        expect(parsedBlockedAt, equals(1720000000000));
      },
    );

    test(
      'unknown method calls on channel do not trigger lock listeners',
      () async {
        bool called = false;
        channel.registerLockRequestListener((pkg, at) => called = true);

        final unknownMessage = const StandardMethodCodec().encodeMethodCall(
          const MethodCall('unknownLifecycleEvent', {'data': 123}),
        );

        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              BlockingPlatformChannel.channelName,
              unknownMessage,
              (ByteData? reply) {},
            );

        expect(called, isFalse);
      },
    );

    test(
      'launchTargetApp returns false when platform channel throws exception',
      () async {
        final result = await channel.launchTargetApp('throw.error.package');
        expect(result, isFalse);
      },
    );
  });

  group('Warm Lock Navigation Routing Challenges', () {
    testWidgets(
      'cold start boots to MainScaffold when initial intent is null',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final fakeChannel = FakeBlockingPlatformChannel();

        await tester.pumpWidget(
          SelfControlApp(
            navigatorKey: navKey,
            platformChannel: fakeChannel,
            initialLockIntent: null,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(MainScaffold), findsOneWidget);
        expect(find.byType(LockedScreen), findsNothing);
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets('warm lock event navigates from MainScaffold to LockedScreen', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      final fakeChannel = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        SelfControlApp(
          navigatorKey: navKey,
          platformChannel: fakeChannel,
          initialLockIntent: null,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MainScaffold), findsOneWidget);

      fakeChannel.triggerLockRequest('com.instagram.android', 1700000000000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LockedScreen), findsOneWidget);
      final lockedScreen = tester.widget<LockedScreen>(
        find.byType(LockedScreen),
      );
      expect(lockedScreen.packageName, equals('com.instagram.android'));
      expect(lockedScreen.startAtEpochMs, equals(1700000000000));
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets(
      'identical warm lock event while already locked does not push duplicate route',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final fakeChannel = FakeBlockingPlatformChannel();

        await tester.pumpWidget(
          SelfControlApp(
            navigatorKey: navKey,
            platformChannel: fakeChannel,
            initialLockIntent: null,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        fakeChannel.triggerLockRequest('com.instagram.android', 1700000000000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LockedScreen), findsOneWidget);

        fakeChannel.triggerLockRequest('com.instagram.android', 1700000001000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LockedScreen), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'different warm lock event replaces active locked screen with new package',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final fakeChannel = FakeBlockingPlatformChannel();

        await tester.pumpWidget(
          SelfControlApp(
            navigatorKey: navKey,
            platformChannel: fakeChannel,
            initialLockIntent: null,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        fakeChannel.triggerLockRequest('com.instagram.android', 1700000000000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LockedScreen), findsOneWidget);
        expect(
          tester.widget<LockedScreen>(find.byType(LockedScreen)).packageName,
          equals('com.instagram.android'),
        );

        fakeChannel.triggerLockRequest(
          'com.zhiliaoapp.musically',
          1700000005000,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(LockedScreen), findsOneWidget);
        expect(
          tester.widget<LockedScreen>(find.byType(LockedScreen)).packageName,
          equals('com.zhiliaoapp.musically'),
        );
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets('empty package name in warm lock event is safely ignored', (
      tester,
    ) async {
      final navKey = GlobalKey<NavigatorState>();
      final fakeChannel = FakeBlockingPlatformChannel();

      await tester.pumpWidget(
        SelfControlApp(
          navigatorKey: navKey,
          platformChannel: fakeChannel,
          initialLockIntent: null,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      fakeChannel.triggerLockRequest('', 1700000000000);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MainScaffold), findsOneWidget);
      expect(find.byType(LockedScreen), findsNothing);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets(
      'cold start initial lock route does not permanently block future warm lock requests for same package',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final fakeChannel = FakeBlockingPlatformChannel();

        await tester.pumpWidget(
          SelfControlApp(
            navigatorKey: navKey,
            platformChannel: fakeChannel,
            initialLockIntent: const {
              'packageName': 'com.cold.app',
              'blockedAt': 1700000000000,
            },
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LockedScreen), findsOneWidget);

        navKey.currentState!.pushReplacementNamed('/');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(LockedScreen), findsNothing);
        expect(find.byType(MainScaffold), findsOneWidget);

        fakeChannel.triggerLockRequest('com.cold.app', 1700000005000);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(LockedScreen), findsOneWidget);
        await tester.pump(const Duration(seconds: 11));
      },
    );

    testWidgets(
      'disposing SelfControlApp unregisters listener without throwing',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final fakeChannel = FakeBlockingPlatformChannel();

        await tester.pumpWidget(
          SelfControlApp(
            navigatorKey: navKey,
            platformChannel: fakeChannel,
            initialLockIntent: null,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(fakeChannel.listeners.length, equals(1));

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.pump(const Duration(seconds: 11));

        expect(fakeChannel.listeners.isEmpty, isTrue);
      },
    );
  });

  group('LockedScreen Target App Redirection Challenges', () {
    testWidgets(
      'successful temporary unlock launches target app and calls onUnlocked',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settingsRepo = FakeSettingsRepository(
          expectedPassword: 'password123',
        );
        final unlockRepo = FakeTemporaryUnlockRepository();
        final logRepo = FakeActivityLogRepository();
        final appRepo = FakeBlockedAppRepository([
          BlockedApp(
            id: 7,
            packageName: 'com.twitter.android',
            appName: 'Twitter',
            createdAt: DateTime(2026),
          ),
        ]);
        final platformChannel = FakeBlockingPlatformChannel();
        final now = DateTime.now().millisecondsSinceEpoch;
        bool onUnlockedFired = false;

        await tester.pumpWidget(
          MaterialApp(
            home: LockedScreen(
              appName: 'Twitter',
              packageName: 'com.twitter.android',
              startAtEpochMs: now - 10000,
              endAtEpochMs: now - 1000,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
              blockedAppRepository: appRepo,
              platformChannel: platformChannel,
              autoOpenModal: true,
              onUnlocked: () => onUnlockedFired = true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PasswordUnlockModal), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'password123');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Buka Sementara'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          platformChannel.lastLaunchedTargetApp,
          equals('com.twitter.android'),
        );
        expect(onUnlockedFired, isTrue);
        expect(unlockRepo.unlocks.single.appId, 7);
        expect(unlockRepo.unlocks.single.isActive, isTrue);
        expect(
          logRepo.logs.single.eventType,
          ActivityLog.eventTemporaryUnlockStarted,
        );
        expect(find.byType(PasswordUnlockModal), findsNothing);
      },
    );

    testWidgets('failed password attempt does not invoke launchTargetApp', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settingsRepo = FakeSettingsRepository(
        expectedPassword: 'secretPassword',
      );
      final unlockRepo = FakeTemporaryUnlockRepository();
      final logRepo = FakeActivityLogRepository();
      final appRepo = FakeBlockedAppRepository();
      final platformChannel = FakeBlockingPlatformChannel();
      final now = DateTime.now().millisecondsSinceEpoch;
      bool onUnlockedFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: LockedScreen(
            appName: 'Instagram',
            packageName: 'com.instagram.android',
            startAtEpochMs: now - 10000,
            endAtEpochMs: now - 1000,
            settingsRepository: settingsRepo,
            temporaryUnlockRepository: unlockRepo,
            activityLogRepository: logRepo,
            blockedAppRepository: appRepo,
            platformChannel: platformChannel,
            autoOpenModal: true,
            onUnlocked: () => onUnlockedFired = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PasswordUnlockModal), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'wrongPassword');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Buka Sementara'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(platformChannel.lastLaunchedTargetApp, isNull);
      expect(onUnlockedFired, isFalse);
    });

    testWidgets(
      'null packageName rejects unlock without granting access or launching an app',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settingsRepo = FakeSettingsRepository(
          expectedPassword: 'validPassword',
        );
        final unlockRepo = FakeTemporaryUnlockRepository();
        final logRepo = FakeActivityLogRepository();
        final appRepo = FakeBlockedAppRepository();
        final platformChannel = _RecordingUnlockChannel();
        final now = DateTime.now().millisecondsSinceEpoch;
        bool onUnlockedFired = false;

        await tester.pumpWidget(
          MaterialApp(
            home: LockedScreen(
              appName: 'General Lock',
              packageName: null,
              appId: 7,
              startAtEpochMs: now - 10000,
              endAtEpochMs: now - 1000,
              settingsRepository: settingsRepo,
              temporaryUnlockRepository: unlockRepo,
              activityLogRepository: logRepo,
              blockedAppRepository: appRepo,
              platformChannel: platformChannel,
              autoOpenModal: true,
              onUnlocked: () => onUnlockedFired = true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PasswordUnlockModal), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'validPassword');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Buka Sementara'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        expect(platformChannel.lastLaunchedTargetApp, isNull);
        expect(platformChannel.grantAttempts, 0);
        expect(onUnlockedFired, isFalse);
        expect(unlockRepo.unlocks, isEmpty);
        expect(logRepo.logs, isEmpty);
        expect(find.byType(PasswordUnlockModal), findsOneWidget);
        expect(find.textContaining('Aplikasi tidak dikenali'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel(BlockingPlatformChannel.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMessageHandler(methodChannel.name, null);
  });

  test(
    'missing native acknowledgement never reports successful blocking',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, (_) async => null);
      final result = await BlockingPlatformChannel().syncBlockedApps([
        'app.test',
      ]);
      expect(result['status'], isNot('success'));
      expect(result['syncedCount'], 0);
    },
  );

  test(
    'platform failure is not an authoritative empty installed app list',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      await expectLater(
        BlockingPlatformChannel().getInstalledApps(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test(
    'null installed app response is an error, explicit empty is valid',
    () async {
      messenger.setMockMethodCallHandler(methodChannel, (_) async => null);
      await expectLater(
        BlockingPlatformChannel().getInstalledApps(),
        throwsA(isA<PlatformException>()),
      );
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => <dynamic>[],
      );
      expect(await BlockingPlatformChannel().getInstalledApps(), isEmpty);
    },
  );

  final invalidCatalogs = <String, Object>{
    'not a list': 'invalid',
    'non-map entry': <Object>['invalid'],
    'null entry': <Object?>[null],
    'missing package': <Object>[
      {'appName': 'Test'},
    ],
    'empty package': <Object>[
      {'packageName': '', 'appName': 'Test'},
    ],
    'blank package': <Object>[
      {'packageName': '  ', 'appName': 'Test'},
    ],
    'non-string package': <Object>[
      {'packageName': 42, 'appName': 'Test'},
    ],
    'missing name': <Object>[
      {'packageName': 'app.test'},
    ],
    'empty name': <Object>[
      {'packageName': 'app.test', 'appName': ''},
    ],
    'blank name': <Object>[
      {'packageName': 'app.test', 'appName': '  '},
    ],
    'non-string name': <Object>[
      {'packageName': 'app.test', 'appName': 42},
    ],
    'non-string key': <Object>[
      {42: 'invalid'},
    ],
  };
  for (final entry in invalidCatalogs.entries) {
    test('installed app catalog rejects ${entry.key}', () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => entry.value,
      );
      await expectLater(
        BlockingPlatformChannel().getInstalledApps(),
        throwsA(isA<PlatformException>()),
      );
    });
  }

  test(
    'installed app catalog preserves valid entries and optional fields',
    () async {
      final apps = <Map<String, dynamic>>[
        {
          'packageName': 'app.test',
          'appName': 'Test',
          'icon': Uint8List.fromList([1, 2]),
        },
        {'packageName': 'app.other', 'appName': 'Other', 'icon': null},
      ];
      messenger.setMockMethodCallHandler(methodChannel, (_) async => apps);
      expect(await BlockingPlatformChannel().getInstalledApps(), apps);
    },
  );

  test(
    'one malformed app rejects the whole catalog rather than hiding it',
    () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => [
          {'packageName': 'app.test', 'appName': 'Test'},
          {'packageName': 'app.bad'},
        ],
      );
      await expectLater(
        BlockingPlatformChannel().getInstalledApps(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  final channel = BlockingPlatformChannel();
  final fallbacks = <String, (Future<Object?> Function(), Object?)>{
    'getBlockingCapability': (
      channel.getBlockingCapability,
      {
        'mode': 'standard',
        'serviceStatus': 'disabled',
        'limitations': <String>[],
      },
    ),
    'getAccessibilityStatus': (channel.getAccessibilityStatus, 'disabled'),
    'isAccessibilityServiceEnabled': (
      channel.isAccessibilityServiceEnabled,
      false,
    ),
    'openAccessibilitySettings': (channel.openAccessibilitySettings, false),
    'syncBlockedApps': (
      () => channel.syncBlockedApps(['app.test']),
      {'syncedCount': 0, 'status': 'failed'},
    ),
    'getCurrentBlockingState': (
      channel.getCurrentBlockingState,
      {'isBlockingActive': false, 'activePackage': null},
    ),
    'getLastBlockingResult': (channel.getLastBlockingResult, 'not_required'),
    'syncTemporaryUnlock': (
      () => channel.syncTemporaryUnlock(
        packageName: 'app.test',
        durationSeconds: 60,
        expiresAtEpochMs: 123,
      ),
      false,
    ),
    'revokeTemporaryUnlock': (
      () => channel.revokeTemporaryUnlock('app.test'),
      false,
    ),
    'syncActiveSessions': (
      () => channel.syncActiveSessions(isStrictSessionActive: true),
      false,
    ),
    'isIgnoringBatteryOptimizations': (
      channel.isIgnoringBatteryOptimizations,
      false,
    ),
    'requestIgnoreBatteryOptimizations': (
      channel.requestIgnoreBatteryOptimizations,
      false,
    ),
    'launchTargetApp': (() => channel.launchTargetApp('app.test'), false),
    'getInitialLockIntent': (channel.getInitialLockIntent, null),
  };
  for (final entry in fallbacks.entries) {
    for (final failure in ['platform error', 'wrong response type', 'null']) {
      test('${entry.key} preserves its safe fallback on $failure', () async {
        messenger.setMockMethodCallHandler(methodChannel, (_) async {
          if (failure == 'platform error') {
            throw PlatformException(code: 'unavailable');
          }
          return failure == 'null' ? null : 42;
        });
        expect(await entry.value.$1(), entry.value.$2);
      });
    }
  }

  for (final operation in [
    'consumePendingBootEvents',
    'consumePendingActivityLogs',
  ]) {
    test('$operation propagates native errors for retry', () async {
      messenger.setMockMethodCallHandler(methodChannel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      await expectLater(
        operation == 'consumePendingBootEvents'
            ? channel.consumePendingBootEvents()
            : channel.consumePendingActivityLogs(),
        throwsA(isA<PlatformException>()),
      );
    });
    test('$operation rejects malformed events', () async {
      messenger.setMockMethodCallHandler(
        methodChannel,
        (_) async => ['invalid'],
      );
      await expectLater(
        operation == 'consumePendingBootEvents'
            ? channel.consumePendingBootEvents()
            : channel.consumePendingActivityLogs(),
        throwsA(anything),
      );
    });
  }

  final lockPayloads = <String, Object?>{
    'null': null,
    'non-map': 'invalid',
    'list': [1],
    'wrong field types': {'packageName': 42, 'blockedAt': 'invalid'},
    'non-finite timestamp': {
      'packageName': 'app.test',
      'blockedAt': double.nan,
    },
    'infinite timestamp': {
      'packageName': 'app.test',
      'blockedAt': double.infinity,
    },
    'missing fields': <String, Object?>{},
  };
  for (final entry in lockPayloads.entries) {
    test('lock event handles ${entry.key} without an error envelope', () async {
      final channel = BlockingPlatformChannel();
      String? package;
      int? timestamp;
      channel.registerLockRequestListener((pkg, at) {
        package = pkg;
        timestamp = at;
      });
      final before = DateTime.now().millisecondsSinceEpoch;
      ByteData? response;
      await messenger.handlePlatformMessage(
        methodChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onLockRequested', entry.value),
        ),
        (reply) => response = reply,
      );
      expect(response, isNotNull);
      expect(const StandardMethodCodec().decodeEnvelope(response!), isNull);
      expect(
        package,
        entry.value is Map && (entry.value as Map)['packageName'] is String
            ? (entry.value as Map)['packageName']
            : '',
      );
      expect(
        timestamp,
        inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch),
      );
    });
  }

  test('valid lock event keeps numeric timestamp conversion', () async {
    final channel = BlockingPlatformChannel();
    String? package;
    int? timestamp;
    channel.registerLockRequestListener((pkg, at) {
      package = pkg;
      timestamp = at;
    });
    await messenger.handlePlatformMessage(
      methodChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'app.test',
          'blockedAt': 1234.75,
        }),
      ),
      (_) {},
    );
    expect(package, 'app.test');
    expect(timestamp, 1234);
  });
}

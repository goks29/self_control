import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/core/platform/blocking_platform_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlockingPlatformChannel M1 Tests', () {
    late BlockingPlatformChannel channel;
    late List<MethodCall> log;

    setUp(() {
      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(BlockingPlatformChannel.channelName),
        (MethodCall call) async {
          log.add(call);
          switch (call.method) {
            case 'launchTargetApp':
              final pkg = call.arguments['packageName'] as String?;
              return pkg != null && pkg.isNotEmpty;
            case 'getInitialLockIntent':
              return {
                'packageName': 'com.instagram.android',
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

    test('launchTargetApp sends correct method and arguments', () async {
      final success = await channel.launchTargetApp('com.instagram.android');

      expect(success, isTrue);
      expect(log, hasLength(1));
      expect(log.first.method, 'launchTargetApp');
      expect(log.first.arguments, {'packageName': 'com.instagram.android'});
    });

    test('launchTargetApp returns false on error or empty package', () async {
      final failure = await channel.launchTargetApp('');
      expect(failure, isFalse);
    });

    test('getInitialLockIntent returns parsed map', () async {
      final intent = await channel.getInitialLockIntent();

      expect(intent, isNotNull);
      expect(intent!['packageName'], 'com.instagram.android');
      expect(intent['blockedAt'], 1700000000000);
      expect(log.last.method, 'getInitialLockIntent');
    });

    test('registerLockRequestListener receives onLockRequested callback', () async {
      String? receivedPackage;
      int? receivedBlockedAt;

      void listener(String pkg, int blockedAt) {
        receivedPackage = pkg;
        receivedBlockedAt = blockedAt;
      }

      channel.registerLockRequestListener(listener);

      final ByteData message = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onLockRequested', {
          'packageName': 'com.tiktok.android',
          'blockedAt': 1600000000000,
        }),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        BlockingPlatformChannel.channelName,
        message,
        (ByteData? reply) {},
      );

      expect(receivedPackage, 'com.tiktok.android');
      expect(receivedBlockedAt, 1600000000000);

      channel.unregisterLockRequestListener(listener);

      receivedPackage = null;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        BlockingPlatformChannel.channelName,
        message,
        (ByteData? reply) {},
      );

      expect(receivedPackage, isNull);
    });
  });
}

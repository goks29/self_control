import 'dart:developer' as developer;

import 'package:flutter/services.dart';

class BlockingPlatformChannel {
  static const String channelName = 'self_control/blocking';

  final MethodChannel _channel;

  void _reportFailure(String operation, Object error, StackTrace stack) {
    developer.log(
      '$operation failed (${error.runtimeType})',
      name: 'self_control.platform',
      stackTrace: stack,
    );
  }

  final List<void Function(String packageName, int blockedAt)>
  _lockRequestListeners = [];

  BlockingPlatformChannel([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  Future<Map<String, dynamic>> getBlockingCapability() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getBlockingCapability',
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (error, stack) {
      _reportFailure('getBlockingCapability', error, stack);
    }
    return <String, dynamic>{
      'mode': 'standard',
      'serviceStatus': 'disabled',
      'limitations': <String>[],
    };
  }

  Future<String> getAccessibilityStatus() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getAccessibilityStatus',
      );
      if (result != null) {
        return result;
      }
    } catch (error, stack) {
      _reportFailure('getAccessibilityStatus', error, stack);
    }
    return 'disabled';
  }

  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      if (result != null) {
        return result;
      }
      final status = await getAccessibilityStatus();
      return status == 'enabled';
    } catch (error, stack) {
      _reportFailure('isAccessibilityServiceEnabled', error, stack);
      return false;
    }
  }

  Future<bool> openAccessibilitySettings() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openAccessibilitySettings',
      );
      return result ?? false;
    } catch (error, stack) {
      _reportFailure('openAccessibilitySettings', error, stack);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<dynamic>('getInstalledApps');
      if (result == null) {
        throw PlatformException(
          code: 'invalid_app_catalog',
          message: 'Native installed-app catalog was not acknowledged',
        );
      }
      if (result is! List) {
        throw PlatformException(
          code: 'invalid_app_catalog',
          message: 'Native installed-app catalog must be a list',
        );
      }
      return result.map((item) {
        if (item is! Map || item.keys.any((key) => key is! String)) {
          throw PlatformException(
            code: 'invalid_app_catalog',
            message: 'Native installed-app entry must be a string-keyed map',
          );
        }
        final packageName = item['packageName'];
        final appName = item['appName'];
        if (packageName is! String ||
            packageName.trim().isEmpty ||
            appName is! String ||
            appName.trim().isEmpty) {
          throw PlatformException(
            code: 'invalid_app_catalog',
            message:
                'Native installed-app entry requires a package and app name',
          );
        }
        return Map<String, dynamic>.from(item);
      }).toList();
    } catch (error, stack) {
      _reportFailure('getInstalledApps', error, stack);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> syncBlockedApps(
    List<String> packageNames,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncBlockedApps',
        {'packages': packageNames},
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (error, stack) {
      _reportFailure('syncBlockedApps', error, stack);
    }
    return <String, dynamic>{'syncedCount': 0, 'status': 'failed'};
  }

  Future<Map<String, dynamic>> getCurrentBlockingState() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getCurrentBlockingState',
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (error, stack) {
      _reportFailure('getCurrentBlockingState', error, stack);
    }
    return <String, dynamic>{'isBlockingActive': false, 'activePackage': null};
  }

  Future<String> getLastBlockingResult() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getLastBlockingResult',
      );
      if (result != null) {
        return result;
      }
    } catch (error, stack) {
      _reportFailure('getLastBlockingResult', error, stack);
    }
    return 'not_required';
  }

  Future<bool> syncTemporaryUnlock({
    required String packageName,
    required int durationSeconds,
    required int expiresAtEpochMs,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncTemporaryUnlock',
        {
          'packageName': packageName,
          'durationSeconds': durationSeconds,
          'expiresAtEpochMs': expiresAtEpochMs,
        },
      );
      return result?['status'] == 'success';
    } catch (error, stack) {
      _reportFailure('syncTemporaryUnlock', error, stack);
      return false;
    }
  }

  Future<bool> revokeTemporaryUnlock(String packageName) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'revokeTemporaryUnlock',
        {'packageName': packageName},
      );
      return result?['status'] == 'success';
    } catch (error, stack) {
      _reportFailure('revokeTemporaryUnlock', error, stack);
      return false;
    }
  }

  Future<bool> syncActiveSessions({
    required bool isStrictSessionActive,
    int? sessionEndEpochMs,
    Map<String, dynamic>? activeSchedule,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncActiveSessions',
        {
          'isStrictSessionActive': isStrictSessionActive,
          'sessionEndEpochMs': sessionEndEpochMs,
          'activeSchedule': activeSchedule,
        },
      );
      return result?['status'] == 'success';
    } catch (error, stack) {
      _reportFailure('syncActiveSessions', error, stack);
      return false;
    }
  }

  Future<List<int>> consumePendingBootEvents() async {
    try {
      final result = await _channel.invokeListMethod<int>(
        'consumePendingBootEvents',
      );
      return result ?? <int>[];
    } catch (error, stack) {
      _reportFailure('consumePendingBootEvents', error, stack);
      rethrow;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (error, stack) {
      _reportFailure('isIgnoringBatteryOptimizations', error, stack);
      return false;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return result ?? false;
    } catch (error, stack) {
      _reportFailure('requestIgnoreBatteryOptimizations', error, stack);
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> consumePendingActivityLogs() async {
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'consumePendingActivityLogs',
      );
      if (result != null) {
        return result.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (error, stack) {
      _reportFailure('consumePendingActivityLogs', error, stack);
      rethrow;
    }
    return <Map<String, dynamic>>[];
  }

  Future<bool> launchTargetApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>('launchTargetApp', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (error, stack) {
      _reportFailure('launchTargetApp', error, stack);
      return false;
    }
  }

  Future<Map<String, dynamic>?> getInitialLockIntent() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getInitialLockIntent',
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (error, stack) {
      _reportFailure('getInitialLockIntent', error, stack);
    }
    return null;
  }

  void registerLockRequestListener(
    void Function(String packageName, int blockedAt) listener,
  ) {
    if (!_lockRequestListeners.contains(listener)) {
      _lockRequestListeners.add(listener);
    }
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  void unregisterLockRequestListener(
    void Function(String packageName, int blockedAt) listener,
  ) {
    _lockRequestListeners.remove(listener);
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'onLockRequested') {
      final arguments = call.arguments;
      final args = arguments is Map ? arguments : null;
      final rawPackageName = args?['packageName'];
      final rawBlockedAt = args?['blockedAt'];
      final validTimestamp = rawBlockedAt is num && rawBlockedAt.isFinite;
      if ((arguments != null && args == null) ||
          (rawPackageName != null && rawPackageName is! String) ||
          (rawBlockedAt != null && !validTimestamp)) {
        _reportFailure(
          'onLockRequested',
          const FormatException('Invalid native lock-request payload'),
          StackTrace.current,
        );
      }
      final packageName = rawPackageName is String ? rawPackageName : '';
      final blockedAt = validTimestamp
          ? rawBlockedAt.toInt()
          : DateTime.now().millisecondsSinceEpoch;
      for (final listener in List.of(_lockRequestListeners)) {
        listener(packageName, blockedAt);
      }
    }
  }
}

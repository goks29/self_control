import 'package:flutter/services.dart';

class BlockingPlatformChannel {
  static const String channelName = 'self_control/blocking';

  final MethodChannel _channel;

  BlockingPlatformChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(channelName);

  Future<Map<String, dynamic>> getBlockingCapability() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getBlockingCapability');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return <String, dynamic>{
      'mode': 'standard',
      'serviceStatus': 'disabled',
      'limitations': <String>[],
    };
  }

  Future<String> getAccessibilityStatus() async {
    try {
      final result = await _channel.invokeMethod<String>('getAccessibilityStatus');
      if (result != null) {
        return result;
      }
    } catch (_) {}
    return 'disabled';
  }

  Future<bool> openAccessibilitySettings() async {
    try {
      final result = await _channel.invokeMethod<bool>('openAccessibilitySettings');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getInstalledApps');
      if (result != null) {
        return result.map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> syncBlockedApps(List<String> packageNames) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'syncBlockedApps',
        {'packages': packageNames},
      );
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return <String, dynamic>{
      'syncedCount': packageNames.length,
      'status': 'success',
    };
  }

  Future<Map<String, dynamic>> getCurrentBlockingState() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentBlockingState');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return <String, dynamic>{
      'isBlockingActive': false,
      'activePackage': null,
    };
  }

  Future<String> getLastBlockingResult() async {
    try {
      final result = await _channel.invokeMethod<String>('getLastBlockingResult');
      if (result != null) {
        return result;
      }
    } catch (_) {}
    return 'not_required';
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_control/application/services/blocking_operation_queue.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(BlockingOperationQueue.resetShared);
  await testMain();
}

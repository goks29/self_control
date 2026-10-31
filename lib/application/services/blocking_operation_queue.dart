import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Runs asynchronous operations one at a time in submission order.
///
/// An idle queue starts an operation synchronously, so callers keep their
/// existing "first await" timing. A failed operation reports its error to its
/// own caller only; later operations still run. Operations must not enqueue
/// work on the same queue and wait for it, because that would deadlock.
class BlockingOperationQueue {
  /// Shared by services that must not interleave native temporary-unlock
  /// changes within this application process.
  static BlockingOperationQueue get shared => _shared;
  static BlockingOperationQueue _shared = BlockingOperationQueue();

  /// Test isolation: an operation left suspended by a torn-down test would
  /// otherwise block every later test in the same isolate.
  @visibleForTesting
  static void resetShared() => _shared = BlockingOperationQueue();

  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  Future<T> run<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    Future<void> start() async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _pending--;
      }
    }

    final previous = _tail;
    final wasIdle = _pending == 0;
    _pending++;
    _tail = result.future.then<void>((_) {}, onError: (Object _) {});
    if (wasIdle) {
      start();
    } else {
      previous.then<void>((_) => start());
    }
    return result.future;
  }
}

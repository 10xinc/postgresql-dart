import 'dart:async';

import 'package:pool/pool.dart';
import 'package:stack_trace/stack_trace.dart';

extension PackagePoolExt on Pool {
  Future<PoolResource> requestWithTimeout(Duration timeout, {String? context}) async {
    final stack = StackTrace.current;
    final completer = Completer<PoolResource>();

    Timer? timer;
    if (timeout > Duration.zero) {
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          final errorMessage = context != null
              ? 'Failed to acquire pool lock. Context: $context'
              : 'Failed to acquire pool lock.';
          completer.completeError(
              TimeoutException(errorMessage), stack);
        }
      });
    }

    final resourceFuture = request();

    scheduleMicrotask(() {
      resourceFuture.then(
        (resource) async {
          timer?.cancel();
          if (completer.isCompleted) {
            resource.release();
            return;
          }
          completer.complete(resource);
        },
        onError: (e, st) {
          timer?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
                e, Chain([Trace.from(st), Trace.from(stack)]));
          }
        },
      );
    });

    return completer.future;
  }

  Future<T> withRequestTimeout<T>(
    FutureOr<T> Function(Duration remainingTimeout) callback, {
    required Duration timeout,
    String? context,
  }) async {
    final sw = Stopwatch()..start();
    final resource = await requestWithTimeout(timeout, context: context);
    final remainingTimeout = timeout - sw.elapsed;
    try {
      return await callback(remainingTimeout);
    } finally {
      resource.release();
    }
  }
}

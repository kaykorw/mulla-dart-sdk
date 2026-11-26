import 'dart:math';

import '../errors.dart';
import 'request.dart';
import 'response.dart';

/// Strategy: decides whether a failed attempt is retried, and how long to wait.
abstract interface class RetryStrategy {
  bool shouldRetry(Request request, int attempt, Response? response, Object? error);

  /// Time to wait before the next attempt.
  Duration delay(int attempt, Response? response);
}

const _safeMethods = ['GET', 'HEAD', 'OPTIONS'];
const _retryableStatuses = [408, 429, 500, 502, 503, 504];
const _notProcessedStatuses = [429, 503];

/// Default strategy: exponential backoff with jitter, honouring Retry-After
/// (but giving up when the server asks to wait longer than [maxDelay]).
///
/// Reads (GET) are retried on network errors, 408, 429 and 5xx.
///
/// Writes (POST/PATCH) are retried ONLY when Mulla cannot have processed them:
/// the connection was never made, or the server answered 429/503 (rejected up front).
/// Repeating a write after a timeout or 500 could create a second charge or payout.
class ExponentialBackoff implements RetryStrategy {
  ExponentialBackoff({
    this.maxRetries = 2,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
    this.jitter = true,
    Random? random,
  }) : _random = random ?? Random();

  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final bool jitter;
  final Random _random;

  @override
  bool shouldRetry(Request request, int attempt, Response? response, Object? error) {
    if (attempt > maxRetries) {
      return false;
    }
    final safe = _safeMethods.contains(request.method);

    if (response == null) {
      if (error is! ConnectionException) {
        return false;
      }

      return safe || !error.requestMayHaveBeenSent;
    }

    final statuses = safe ? _retryableStatuses : _notProcessedStatuses;
    if (!statuses.contains(response.statusCode)) {
      return false;
    }
    final retryAfter = _retryAfter(response);

    return retryAfter == null || retryAfter <= maxDelay;
  }

  @override
  Duration delay(int attempt, Response? response) {
    final retryAfter = response != null ? _retryAfter(response) : null;
    if (retryAfter != null) {
      return retryAfter;
    }
    var ms = min(maxDelay.inMilliseconds, baseDelay.inMilliseconds * pow(2, attempt - 1)).toDouble();
    if (jitter) {
      ms *= 0.5 + _random.nextDouble() * 0.5;
    }

    return Duration(milliseconds: ms.round());
  }
}

Duration? _retryAfter(Response response) {
  final value = response.header('retry-after');
  final seconds = value == null ? null : num.tryParse(value.trim());

  return seconds == null || !seconds.isFinite ? null : Duration(milliseconds: (seconds * 1000).round());
}

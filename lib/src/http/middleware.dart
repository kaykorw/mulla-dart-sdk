import '../errors.dart';
import '../support/redactor.dart';
import '../support/runtime.dart';
import '../support/uuid.dart';
import '../version.dart';
import 'request.dart';
import 'response.dart';
import 'retry.dart';
import 'transport.dart';

typedef Next = Future<Response> Function(Request request);

/// Chain of Responsibility handler. Each middleware may change the request,
/// call [next] to continue the chain, and inspect or replace the response.
///
/// Add your own (e.g. tracing) through the client's `middleware` option,
/// either by implementing this interface or with [Middleware.fn].
abstract interface class Middleware {
  /// Wraps a plain function as a middleware.
  factory Middleware.fn(Future<Response> Function(Request request, Next next) handler) = _FunctionMiddleware;

  Future<Response> handle(Request request, Next next);
}

class _FunctionMiddleware implements Middleware {
  _FunctionMiddleware(this._handler);

  final Future<Response> Function(Request request, Next next) _handler;

  @override
  Future<Response> handle(Request request, Next next) => _handler(request, next);
}

/// Runs a request through the middleware list (outermost first), then the transport.
class Pipeline {
  Pipeline(Transport transport, [List<Middleware> middleware = const []]) {
    Next next = transport.send;
    for (final layer in middleware.reversed) {
      final inner = next;
      next = (request) => layer.handle(request, inner);
    }
    _handler = next;
  }

  late final Next _handler;

  Future<Response> send(Request request) => _handler(request);
}

/// Adds the `x-api-key` header.
class AuthMiddleware implements Middleware {
  AuthMiddleware(this._apiKey);

  static const header = 'x-api-key';
  final String _apiKey;

  @override
  Future<Response> handle(Request request, Next next) => next(request.withHeader(header, _apiKey));

  @override
  String toString() => 'AuthMiddleware(apiKey: ****)';
}

/// Adds the device/platform/user-agent/language headers Mulla expects on every call.
class ClientContextMiddleware implements Middleware {
  ClientContextMiddleware(this.deviceId, {this.lang, this.appInfo});

  final String deviceId;
  final String? lang;
  final String? appInfo;

  @override
  Future<Response> handle(Request request, Next next) {
    final agent = '$sdkPlatform/$sdkVersion ${runtimeName()}';
    final headers = <String, String>{
      'accept': 'application/json',
      'user-agent': appInfo != null ? '$agent $appInfo' : agent,
      'x-platform': '$sdkPlatform/$sdkVersion',
      'x-device-id': deviceId,
      if (request.body != null) 'content-type': 'application/json',
      if (lang != null) 'x-lang': lang!,
      if (lang != null) 'accept-language': lang!,
    };

    var current = request;
    headers.forEach((name, value) {
      if (!current.hasHeader(name)) {
        current = current.withHeader(name, value);
      }
    });

    return next(current);
  }
}

/// Gives every POST an idempotency key (kept across retries).
class IdempotencyMiddleware implements Middleware {
  static const header = 'x-idempotency-key';

  @override
  Future<Response> handle(Request request, Next next) {
    if (request.method == 'POST' && !request.hasHeader(header)) {
      return next(request.withHeader(header, uuidV4()));
    }

    return next(request);
  }
}

typedef Sleep = Future<void> Function(Duration duration);

Future<void> defaultSleep(Duration duration) =>
    duration > Duration.zero ? Future<void>.delayed(duration) : Future<void>.value();

/// Retries attempts that the [RetryStrategy] allows.
class RetryMiddleware implements Middleware {
  RetryMiddleware(this.strategy, [this.sleep = defaultSleep]);

  final RetryStrategy strategy;
  final Sleep sleep;

  @override
  Future<Response> handle(Request request, Next next) async {
    for (var attempt = 1;; attempt++) {
      Response? response;
      ConnectionException? error;

      try {
        response = await next(request.withAttribute('attempt', attempt));
      } on ConnectionException catch (e) {
        error = e;
      }

      if (!strategy.shouldRetry(request, attempt, response, error)) {
        if (response == null) {
          throw error!;
        }

        return response;
      }

      await sleep(strategy.delay(attempt, response));
    }
  }
}

enum LogLevel { debug, info, warn, error }

/// Receives SDK log lines. Keys, tokens and bodies are never passed to it.
typedef MullaLogger = void Function(LogLevel level, String message, Map<String, Object?> context);

/// Logs each attempt (method, redacted URL, status, duration).
class LoggingMiddleware implements Middleware {
  LoggingMiddleware(MullaLogger logger)
      : _log = ((level, message, context) {
          try {
            logger(level, message, context);
          } on Object {
            // A failing logger must never break a payment.
          }
        });

  final MullaLogger _log;

  @override
  Future<Response> handle(Request request, Next next) async {
    final watch = Stopwatch()..start();
    final url = redactUrl(request.url);
    final context = <String, Object?>{
      'method': request.method,
      'url': url,
      'attempt': request.attribute<int>('attempt', 1),
      'idempotencyKey': request.header(IdempotencyMiddleware.header),
    };

    final Response response;
    try {
      response = await next(request);
    } on ConnectionException catch (error) {
      _log(LogLevel.warn, 'Mulla request failed: ${error.message}',
          {...context, 'durationMs': watch.elapsedMilliseconds});
      rethrow;
    }

    final level =
        response.isSuccessful ? LogLevel.debug : (response.statusCode >= 500 ? LogLevel.error : LogLevel.warn);
    _log(level, 'Mulla ${request.method} $url -> ${response.statusCode}', {
      ...context,
      'status': response.statusCode,
      'durationMs': watch.elapsedMilliseconds,
    });

    return response;
  }
}

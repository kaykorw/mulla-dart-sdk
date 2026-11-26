import 'dart:async';
import 'dart:convert';

import '../config.dart';
import '../enums.dart';
import '../errors.dart';
import '../http/request_options.dart';
import '../http/requestor.dart';
import '../http/sse.dart';
import '../models/collection.dart';
import '../models/model.dart';
import '../params.dart';
import '../support/normalizer.dart';
import '../support/runtime.dart';

/// Template Method base for every service: subclasses only describe endpoints;
/// validation, error translation, paging and polling live here.
abstract class AbstractService {
  AbstractService(this.requestor);

  final ApiRequestor requestor;

  MullaConfig get config => requestor.config;

  /// Name used in error messages, e.g. `charges`.
  String get resource;

  /// Scope the endpoints need, named in permission errors.
  ApiScope? get scope => null;

  Future<Object?> callApi(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    RequestOptions? options,
  }) async {
    final opts = options ?? const RequestOptions();
    opts.validate();
    try {
      return await requestor.request(method, path, query: query, body: body, options: opts);
    } on PermissionException catch (error) {
      throw _explainScope(error);
    }
  }

  Future<T> send<T extends Model>(
    ModelFactory<T> factory,
    String name,
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    RequestOptions? options,
  }) async =>
      makeModel(factory, await callApi(method, path, query: query, body: body, options: options), name);

  Future<Collection<T>> listModels<T extends Model>(
    ModelFactory<T> factory,
    String path,
    ListFilters? filters,
    RequestOptions? options,
  ) async {
    final query = filters?.toApi() ?? const <String, Object?>{};
    Future<Collection<T>> fetchPage(int page) async => Collection.fromResponse(
        factory, await callApi('GET', path, query: {...query, 'page': page}, options: options), fetchPage);

    return Collection.fromResponse(factory, await callApi('GET', path, query: query, options: options), fetchPage);
  }

  Future<T> pollUntilFinal<T>(
    Future<T> Function() fetch,
    bool Function(T model) isFinal, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 5),
  }) async {
    if (interval < const Duration(seconds: 1) || timeout.isNegative) {
      throw InvalidArgumentException('Polling "interval" must be at least 1 second and "timeout" not negative.');
    }
    final deadline = DateTime.now().add(timeout);
    for (;;) {
      final model = await fetch();
      final left = deadline.difference(DateTime.now());
      if (isFinal(model) || left <= Duration.zero) {
        return model;
      }
      await config
          .sleep(interval < left ? interval : (left < const Duration(seconds: 1) ? const Duration(seconds: 1) : left));
    }
  }

  /// How long a server-sent events stream may stay silent (not even a keepalive)
  /// before it is treated as stalled and [watchUpdates] switches to polling.
  static const streamIdleTimeout = Duration(seconds: 45);

  /// Live updates: server-sent events, falling back to polling [poll] when streaming
  /// is unavailable (browsers buffer streamed responses), drops or goes silent.
  /// The stream closes after the first final update.
  Stream<U> watchUpdates<U>({
    required String path,
    Map<String, Object?> query = const {},
    required U Function(RawData data) parse,
    required bool Function(U update) isFinal,
    required String? Function(U update) statusOf,
    required Future<U> Function() poll,
    Duration pollInterval = const Duration(seconds: 3),
    bool? useServerSentEvents,
    Duration idleTimeout = streamIdleTimeout,
  }) {
    late StreamController<U> controller;
    StreamSubscription<SseEvent>? subscription;
    Timer? timer;
    Timer? idle;
    var closed = false;
    var polling = false;
    String? lastStatus;

    void emit(U update) {
      if (closed) return;
      final status = statusOf(update);
      if (status != lastStatus) {
        lastStatus = status;
        controller.add(update);
      }
      if (isFinal(update)) {
        closed = true;
        timer?.cancel();
        idle?.cancel();
        unawaited(subscription?.cancel());
        unawaited(controller.close());
      }
    }

    void startPolling() {
      idle?.cancel();
      if (closed || timer != null) return;
      final stream = subscription;
      subscription = null;
      unawaited(stream?.cancel());
      Future<void> tick() async {
        // A slow response must not stack up overlapping requests.
        if (polling || closed) return;
        polling = true;
        try {
          emit(await poll());
        } on ConnectionException {
          // Temporary network problem: try again on the next tick.
        } on Object catch (error, stack) {
          if (!closed) controller.addError(error, stack);
        } finally {
          polling = false;
        }
      }

      unawaited(tick());
      timer = Timer.periodic(pollInterval, (_) => unawaited(tick()));
    }

    Future<void> startStream() async {
      try {
        final response = await requestor.openStream(path, query: query);
        if (closed) {
          // Cancelled while connecting: drop the connection.
          unawaited(response.stream.listen(null).cancel());

          return;
        }
        // Any bytes (events or keepalive comments) prove the connection is alive.
        void stillAlive() {
          idle?.cancel();
          if (!closed) idle = Timer(idleTimeout, startPolling);
        }

        stillAlive();
        subscription = parseSse(response.stream.map((chunk) {
          stillAlive();

          return chunk;
        })).listen(
          (event) {
            final Object? decoded;
            try {
              decoded = jsonDecode(event.data);
            } on FormatException {
              return;
            }
            if (decoded is! Map || decoded['type'] == 'ping') return;
            emit(parse(decoded.cast<String, Object?>()));
          },
          onError: (Object _) => startPolling(),
          onDone: startPolling,
          cancelOnError: true,
        );
      } on ApiException catch (error, stack) {
        // 4xx (bad token, unknown id) will not fix itself: report it.
        if (error.statusCode < 500) {
          if (!closed) controller.addError(error, stack);
          closed = true;
          unawaited(controller.close());
        } else {
          startPolling();
        }
      } on Object {
        startPolling();
      }
    }

    controller = StreamController<U>(
      onListen: () {
        if (useServerSentEvents ?? !isWeb) {
          unawaited(startStream());
        } else {
          startPolling();
        }
      },
      onCancel: () async {
        closed = true;
        timer?.cancel();
        idle?.cancel();
        await subscription?.cancel();
      },
    );

    return controller.stream;
  }

  /// Validates and URL-encodes a path id.
  static String id(String id, [String label = 'id']) {
    if (id.trim().isEmpty) {
      throw InvalidArgumentException('The $label cannot be empty.');
    }
    if (id == '.' || id == '..') {
      throw InvalidArgumentException('The $label "$id" is not valid.');
    }

    return encodeRfc3986(id);
  }

  PermissionException _explainScope(PermissionException error) {
    if (error.errorCode != 'API_KEY_SCOPE_DENIED') {
      return error;
    }
    final body = error.body ?? const {};
    final missing = body['missing'];
    var required = body['requiredScope'] ?? body['required_scope'] ?? (missing is List ? missing.join(', ') : null);
    if (required is! String || required.isEmpty) {
      required = scope?.value;
    }
    if (required == null) {
      return error;
    }

    return PermissionException(
      '${error.message} Required scope: $required.',
      statusCode: error.statusCode,
      errorCode: error.errorCode,
      body: error.body,
      headers: error.headers,
      rawBody: error.rawBody,
      cause: error,
    );
  }

  @override
  String toString() => '$runtimeType(baseUrl: ${config.baseUrl})';
}

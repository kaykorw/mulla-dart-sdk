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

/// Shared base for services: validation, error translation, paging and polling.
abstract class AbstractService {
  /// Creates a service that sends requests through [requestor].
  AbstractService(this.requestor);

  /// Sends the requests and turns error responses into exceptions.
  final ApiRequestor requestor;

  /// The client settings.
  MullaConfig get config => requestor.config;

  /// Name used in error messages, e.g. `charges`.
  String get resource;

  /// Scope the endpoints need, named in permission errors.
  ApiScope? get scope => null;

  /// Sends a request and returns the decoded JSON body.
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

  /// Sends a request and builds a model from the response.
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

  /// Fetches one page of a list endpoint.
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

  /// Calls [fetch] every [interval] until [isFinal] or [timeout].
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

  /// Silence after which a live stream is treated as stalled and replaced by polling.
  static const streamIdleTimeout = Duration(seconds: 45);

  /// Live updates over server-sent events, falling back to polling.
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
        if (polling || closed) return;
        polling = true;
        try {
          emit(await poll());
        } on ConnectionException {
          // Temporary network problem: the next tick retries.
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
          unawaited(response.stream.listen(null).cancel());

          return;
        }
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

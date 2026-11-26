import 'dart:convert';

import '../config.dart';
import '../errors.dart';
import '../support/normalizer.dart';
import 'middleware.dart';
import 'request.dart';
import 'request_options.dart';
import 'response.dart';
import 'transport.dart';

/// Builds requests, runs them through the middleware pipeline and turns error responses into exceptions.
class ApiRequestor {
  ApiRequestor(this.config)
      : _context = ClientContextMiddleware(config.deviceId, lang: config.lang?.value, appInfo: config.appInfo) {
    _pipeline = Pipeline(config.transport, [
      _context,
      if (!config.isPublic) AuthMiddleware(config.apiKey()),
      IdempotencyMiddleware(),
      RetryMiddleware(config.retryStrategy, config.sleep),
      ...config.middleware,
      if (config.logger != null) LoggingMiddleware(config.logger!),
    ]);
  }

  final MullaConfig config;
  final ClientContextMiddleware _context;
  late final Pipeline _pipeline;

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    RequestOptions options = const RequestOptions(),
  }) async {
    final response = await _pipeline.send(build(method, path, query: query, body: body, options: options));
    if (!response.isSuccessful) {
      throw exceptionFromResponse(response);
    }

    return response.json();
  }

  Future<StreamedResponse> openStream(String path, {Map<String, Object?> query = const {}}) async {
    final transport = config.transport;
    if (transport is! StreamingTransport) {
      throw InvalidArgumentException('The configured transport does not support streaming (server-sent events).');
    }
    var request = build('GET', path, query: query).withHeader('accept', 'text/event-stream');
    await _context.handle(request, (r) async {
      request = r;

      return Response(204);
    });
    final response = await transport.openStream(request);
    if (!response.isSuccessful) {
      throw exceptionFromResponse(await response.toResponse());
    }

    return response;
  }

  String url(String path, [Map<String, Object?> query = const {}]) =>
      '${config.baseUrl}/${path.replaceFirst(RegExp('^/+'), '')}${buildQuery(query)}';

  Request build(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Map<String, Object?>? body,
    RequestOptions options = const RequestOptions(),
  }) {
    final headers = <String, String>{
      for (final e in options.headers.entries) e.key.toLowerCase(): e.value,
      if (options.idempotencyKey != null) IdempotencyMiddleware.header: options.idempotencyKey!,
      if (options.lang != null) 'x-lang': options.lang!.value,
      if (options.lang != null) 'accept-language': options.lang!.value,
    };

    return Request(
      method: method,
      url: url(path, query),
      headers: headers,
      body: body != null ? jsonEncode(normalize(body)) : null,
      timeout: options.timeout ?? config.timeout,
      abortTrigger: options.abortTrigger,
    );
  }
}

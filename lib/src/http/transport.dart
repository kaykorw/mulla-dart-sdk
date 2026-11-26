import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../support/redactor.dart';
import 'request.dart';
import 'response.dart';

abstract interface class Transport {
  Future<Response> send(Request request);
}

/// A transport that can also keep a response open (server-sent events).
abstract interface class StreamingTransport implements Transport {
  Future<StreamedResponse> openStream(Request request);
}

const _notSentMarkers = [
  'Failed host lookup',
  'No address associated',
  'nodename nor servname',
  'Connection refused',
  'No route to host',
  'Network is unreachable',
  'CERTIFICATE_VERIFY_FAILED',
  'HandshakeException',
  'TlsException',
];

/// Default transport, built on `package:http`.
class HttpTransport implements StreamingTransport {
  HttpTransport([http.Client? client]) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<Response> send(Request request) async {
    final timeout = Completer<void>();
    var timedOut = false;
    final timer = Timer(request.timeout, () {
      timedOut = true;
      timeout.complete();
    });
    final userAbort = request.abortTrigger;
    final abort = userAbort == null ? timeout.future : Future.any([timeout.future, userAbort]);

    try {
      final streamed = await _client.send(_build(request, abort));
      final body = await utf8.decodeStream(streamed.stream);

      return Response(streamed.statusCode, headers: streamed.headers, body: body);
    } on Object catch (error) {
      throw _translate(request, error, timedOut: timedOut);
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<StreamedResponse> openStream(Request request) async {
    final timeout = Completer<void>();
    var timedOut = false;
    final timer = Timer(request.timeout, () {
      timedOut = true;
      timeout.complete();
    });
    final userAbort = request.abortTrigger;
    final abort = userAbort == null ? timeout.future : Future.any([timeout.future, userAbort]);

    try {
      final streamed = await _client.send(_build(request, abort));

      return StreamedResponse(streamed.statusCode, headers: streamed.headers, stream: streamed.stream);
    } on Object catch (error) {
      throw _translate(request, error, timedOut: timedOut);
    } finally {
      timer.cancel();
    }
  }

  void close() => _client.close();

  http.BaseRequest _build(Request request, Future<void>? abort) {
    final r = http.AbortableRequest(request.method, Uri.parse(request.url), abortTrigger: abort)
      ..followRedirects = false
      ..headers.addAll(request.headers);
    final body = request.body;
    if (body != null) {
      r.bodyBytes = utf8.encode(body);
    }

    return r;
  }

  Object _translate(Request request, Object error, {required bool timedOut}) {
    if (error is MullaException) {
      return error;
    }
    if (error is http.RequestAbortedException && !timedOut) {
      return RequestCancelledException('The Mulla request was cancelled.', cause: error);
    }
    final text = '$error';
    final notSent = !timedOut && _notSentMarkers.any(text.contains);
    final reason = timedOut ? 'timed out after ${request.timeout.inMilliseconds} ms' : text;

    var message = 'Could not reach Mulla at ${redactUrl(request.url)} ($reason).';
    if (!notSent && request.method != 'GET') {
      message += ' The request may have reached Mulla: check whether it was processed before sending it again.';
    }

    return ConnectionException(message, requestMayHaveBeenSent: !notSent, cause: error);
  }
}

/// Test helpers: fake the Mulla API and sign webhooks without network access.
library;

import 'dart:async';
import 'dart:convert';

import 'mulla_dart.dart';

typedef _Handler = FutureOr<Response> Function(Request request);

/// In-memory transport for testing code that uses the SDK.
class FakeTransport implements StreamingTransport {
  final List<Object> _queue = [];
  final List<Object> _streams = [];
  final List<Request> _sent = [];

  FakeTransport pushJson(Object? body, {int status = 200, Map<String, String> headers = const {}}) =>
      push(Response(status, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body)));

  /// Queues an API error in Mulla's format.
  FakeTransport pushError(int status, String errorCode,
          {String message = 'Error', Map<String, Object?> extra = const {}}) =>
      pushJson({'statusCode': status, 'message': message, 'errorCode': errorCode, ...extra}, status: status);

  FakeTransport pushConnectionError({String message = 'Connection refused', bool requestMayHaveBeenSent = false}) =>
      push(ConnectionException(message, requestMayHaveBeenSent: requestMayHaveBeenSent));

  /// Queues a [Response], an exception, or a `(Request) => Response` function.
  FakeTransport push(Object response) {
    if (response is! Response && response is! Exception && response is! _Handler) {
      throw ArgumentError('push() takes a Response, an Exception or a (Request) => Response function.');
    }
    _queue.add(response);

    return this;
  }

  /// Queues a server-sent events stream: each map becomes one `data:` event.
  FakeTransport pushEvents(List<Map<String, Object?>> events, {bool keepOpen = false}) {
    _streams.add(_SseScript(events, keepOpen));

    return this;
  }

  /// Queues a stream fed by [controller] (each added map is one event).
  FakeTransport pushEventController(StreamController<Map<String, Object?>> controller) {
    _streams.add(controller);

    return this;
  }

  FakeTransport pushStreamError(Object error) {
    _streams.add(error);

    return this;
  }

  @override
  Future<Response> send(Request request) async {
    _sent.add(request);
    if (_queue.isEmpty) {
      throw StateError(
          'FakeTransport has no queued response for ${request.method} ${request.url}. Queue one with pushJson().');
    }
    final next = _queue.removeAt(0);
    if (next is Response) return next;
    if (next is _Handler) return next(request);
    throw next;
  }

  @override
  Future<StreamedResponse> openStream(Request request) async {
    _sent.add(request);
    if (_streams.isEmpty) {
      throw ConnectionException('FakeTransport has no queued event stream for ${request.url}.',
          requestMayHaveBeenSent: false);
    }
    final next = _streams.removeAt(0);
    if (next is _SseScript) {
      return StreamedResponse(200, headers: const {'content-type': 'text/event-stream'}, stream: next.bytes());
    }
    if (next is StreamController<Map<String, Object?>>) {
      return StreamedResponse(200,
          headers: const {'content-type': 'text/event-stream'},
          stream: next.stream.map((e) => utf8.encode('data: ${jsonEncode(e)}\n\n')));
    }
    throw next;
  }

  List<Request> get requests => List.unmodifiable(_sent);

  Request? get lastRequest => _sent.isEmpty ? null : _sent.last;

  Object? get lastBody {
    final body = lastRequest?.body;

    return body == null ? null : jsonDecode(body);
  }

  void assertSent(bool Function(Request request) matcher) {
    if (!_sent.any(matcher)) {
      throw StateError('Expected a matching request to be sent to Mulla, but none was. Sent: ${_describe()}');
    }
  }

  void assertSentCount(int count) {
    if (_sent.length != count) {
      throw StateError('Expected $count request(s) to Mulla, got ${_sent.length}. Sent: ${_describe()}');
    }
  }

  void assertNothingSent() => assertSentCount(0);

  String _describe() => _sent.isEmpty ? '(none)' : _sent.map((r) => '${r.method} ${r.url}').join(', ');
}

class _SseScript {
  _SseScript(this.events, this.keepOpen);

  final List<Map<String, Object?>> events;
  final bool keepOpen;

  Stream<List<int>> bytes() async* {
    for (final e in events) {
      yield utf8.encode('data: ${jsonEncode(e)}\n\n');
    }
    if (keepOpen) {
      await Completer<void>().future;
    }
  }
}

class SignedWebhook {
  const SignedWebhook(this.body, this.headers);

  final String body;
  final Map<String, String> headers;
}

/// Builds correctly signed webhook requests so you can test your webhook route.
abstract final class WebhookSigner {
  static SignedWebhook event(String type, Map<String, Object?> data, String secret, {String? eventId, int? timestamp}) {
    final body = jsonEncode({'event': type, 'event_id': eventId ?? uuidV4(), 'data': data});

    return SignedWebhook(body, headers(body, secret, timestamp: timestamp));
  }

  static Map<String, String> headers(String body, String secret, {int? timestamp}) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final bytes = utf8.encode(body);

    return {
      'content-type': 'application/json',
      V1SignatureVerifier.header: V1SignatureVerifier.sign(bytes, secret),
      V2SignatureVerifier.timestampHeader: '$ts',
      V2SignatureVerifier.signatureHeader: V2SignatureVerifier.sign(bytes, secret, ts),
    };
  }

  static Map<String, String> v1Headers(String body, String secret) => {
        'content-type': 'application/json',
        V1SignatureVerifier.header: V1SignatureVerifier.sign(utf8.encode(body), secret),
      };
}

/// Ready-made API payloads for tests.
abstract final class MullaFixtures {
  static Map<String, Object?> checkoutSession({
    String id = 'cs_test_1',
    String status = 'PENDING',
    num amount = 5000,
    String? provider,
    String? phoneNumber,
    DateTime? expiresAt,
  }) =>
      {
        'id': id,
        'charge': 'chg_test_1',
        'reference': 'CHG-TEST-1',
        'amount': amount,
        'currency': 'RWF',
        'reason': 'Order #1001',
        'status': status,
        'token': 'tok_test',
        'provider': provider,
        'phone_number': phoneNumber,
        'merchant': {'name': 'Test Shop'},
        'expires_at': (expiresAt ?? DateTime.now().add(const Duration(minutes: 15))).toUtc().toIso8601String(),
      };

  static Map<String, Object?> invoice({String id = 'inv_test_1', String status = 'ISSUED', num total = 12000}) => {
        'id': id,
        'invoice_number': 'INV-0001',
        'status': status,
        'customer_name': 'Jane Doe',
        'total_amount': total,
        'amount_paid': status == 'PAID' ? total : 0,
        'currency': 'RWF',
        'items': [
          {'name': 'Website design', 'unit_price': total, 'quantity': 1, 'amount': total},
        ],
        'merchant': {'name': 'Test Shop'},
      };
}

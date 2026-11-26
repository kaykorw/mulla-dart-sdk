import 'dart:async';
import 'dart:convert';

import '../enums.dart';
import '../errors.dart';
import 'event.dart';
import 'verifiers.dart';

/// Verifies incoming webhook requests and turns them into [Event]s.
class Webhook {
  Webhook(String secret, {int toleranceSeconds = 300, List<SignatureVerifier>? verifiers})
      : _secret = secret,
        _verifiers =
            verifiers ?? [V2SignatureVerifier(toleranceSeconds: toleranceSeconds), const V1SignatureVerifier()] {
    if (secret.isEmpty) {
      throw InvalidArgumentException(
        'Webhook secret is empty. Use the secret shown when you created or rotated your webhook endpoint.',
      );
    }
  }

  final String _secret;
  final List<SignatureVerifier> _verifiers;

  /// [payload] is the raw body: a `String` or bytes (`List<int>`), never parsed JSON.
  static Event constructEvent(Object payload, Map<String, String> headers, String secret,
          {int toleranceSeconds = 300}) =>
      Webhook(secret, toleranceSeconds: toleranceSeconds).parse(payload, headers);

  Event parse(Object payload, Map<String, String> headers) {
    final List<int> bytes;
    if (payload is String) {
      bytes = utf8.encode(payload);
    } else if (payload is List<int>) {
      bytes = payload;
    } else {
      throw SignatureVerificationException(
        'The webhook payload must be the raw request body (String or bytes), not parsed JSON.',
      );
    }
    final normalized = {for (final e in headers.entries) e.key.toLowerCase(): e.value};

    _verify(bytes, normalized);

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map || !decoded.containsKey('event')) {
      throw SignatureVerificationException('Webhook body is not a valid Mulla event.');
    }

    return Event.fromPayload(decoded.cast<String, Object?>());
  }

  void _verify(List<int> payload, Map<String, String> headers) {
    for (final verifier in _verifiers) {
      if (verifier.supports(headers)) {
        verifier.verify(payload, headers, _secret);

        return;
      }
    }

    throw SignatureVerificationException(
      'No Mulla signature header found (expected "x-webhook-signature"). Is this request really from Mulla?',
    );
  }

  @override
  String toString() => 'Webhook(secret: ****)';
}

typedef EventListener = FutureOr<void> Function(Event event);

/// Routes events to listeners by type.
class EventDispatcher {
  final Map<String, List<EventListener>> _listeners = {};

  static const _any = '*';

  EventDispatcher on(WebhookEventType type, EventListener listener) => onType(type.value, listener);

  /// Listens to an event type by name (also for types newer than this SDK).
  EventDispatcher onType(String type, EventListener listener) {
    (_listeners[type] ??= []).add(listener);

    return this;
  }

  EventDispatcher onAny(EventListener listener) => onType(_any, listener);

  bool hasListeners(String type) => _listeners.containsKey(type) || _listeners.containsKey(_any);

  /// Runs the matching listeners one after another; returns how many ran.
  Future<int> dispatch(Event event) async {
    final listeners = [...?_listeners[event.type], ...?_listeners[_any]];
    for (final listener in listeners) {
      await listener(event);
    }

    return listeners.length;
  }
}

/// The reply a webhook route should send.
class WebhookResult {
  const WebhookResult(this.status, this.body, this.event);

  /// 200 (handled or duplicate), 400 (bad signature) or 500 (a listener threw: Mulla retries).
  final int status;
  final Map<String, Object?> body;
  final Event? event;

  String get jsonBody => jsonEncode(body);
}

/// Framework-independent webhook handling: verifies the raw body, skips duplicates and runs the listeners.
class WebhookProcessor {
  WebhookProcessor({
    required String secret,
    EventDispatcher? dispatcher,
    this.isDuplicate,
    void Function(Object error, StackTrace stack, Event event)? onError,
    int toleranceSeconds = 300,
  })  : _webhook = Webhook(secret, toleranceSeconds: toleranceSeconds),
        dispatcher = dispatcher ?? EventDispatcher(),
        _onError = onError ?? _printError;

  final Webhook _webhook;
  final EventDispatcher dispatcher;

  /// Return true for events you already handled (Mulla may deliver one more than once).
  final FutureOr<bool> Function(Event event)? isDuplicate;
  final void Function(Object error, StackTrace stack, Event event) _onError;

  Future<WebhookResult> call(Object rawBody, Map<String, String> headers) async {
    final Event event;
    try {
      event = _webhook.parse(rawBody, headers);
    } on SignatureVerificationException catch (error) {
      return WebhookResult(400, {'received': false, 'error': error.message}, null);
    }

    try {
      final check = isDuplicate;
      if (check != null && await check(event)) {
        return WebhookResult(200, const {'received': true, 'duplicate': true}, event);
      }
      await dispatcher.dispatch(event);
    } on Object catch (error, stack) {
      _onError(error, stack, event);

      return WebhookResult(500, const {'received': false, 'error': 'Webhook handler failed'}, event);
    }

    return WebhookResult(200, const {'received': true}, event);
  }

  static void _printError(Object error, StackTrace stack, Event event) {
    // ignore: avoid_print
    print('[mulla] Webhook listener failed for ${event.type} ${event.id}: $error');
  }
}

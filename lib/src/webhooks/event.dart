import 'dart:collection';

import '../enums.dart';

/// A verified webhook event.
class Event {
  Event({required this.id, required this.type, Map<String, Object?> data = const {}})
      : data = UnmodifiableMapView(Map.of(data)),
        eventType = WebhookEventType.tryParse(type);

  factory Event.fromPayload(Map<String, Object?> payload) {
    final data = payload['data'];

    return Event(
      id: _scalar(payload['event_id']) ?? '',
      type: _scalar(payload['event']) ?? '',
      data: data is Map ? data.cast<String, Object?>() : const {},
    );
  }

  final String id;
  final String type;
  final Map<String, Object?> data;

  /// The typed event, or null for an event type this SDK version does not know.
  final WebhookEventType? eventType;

  bool isType(WebhookEventType type) => this.type == type.value;

  bool get isTest => eventType == WebhookEventType.webhookTest;
  bool get isCharge => type.startsWith('charge.');
  bool get isPayout => type.startsWith('payout.');
  bool get isInvoice => type.startsWith('invoice.');

  /// The charge, payout or invoice id. Use it to find your own record.
  String? objectId() {
    for (final key in const ['charge', 'payout', 'invoice']) {
      final value = data[key];
      final id = _scalar(value);
      if (id != null) {
        return id;
      }
      if (value is Map) {
        final nested = _scalar(value['id']);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  String? reference() => _scalar(data['reference']);
  String? transactionId() => _scalar(data['transaction_id']);
  String? status() => _scalar(data['status']);
  String? currency() => _scalar(data['currency']);

  num? amount() {
    final value = data['amount'];
    if (value is num) return value.isFinite ? value : null;
    if (value is String) return num.tryParse(value.trim());

    return null;
  }

  Map<String, Object?>? metadata() {
    final value = data['metadata'];

    return value is Map ? value.cast<String, Object?>() : null;
  }

  Map<String, Object?> toJson() => {'event': type, 'event_id': id, 'data': Map.of(data)};

  @override
  String toString() => 'Event($type, $id)';
}

String? _scalar(Object? value) => value is String || value is num || value is bool ? '$value' : null;

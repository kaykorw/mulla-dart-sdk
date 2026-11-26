import 'dart:convert';
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';
import 'package:test/test.dart';

final Map<String, Object?> v =
    jsonDecode(File('test/fixtures/webhooks/charge_success.json').readAsStringSync()) as Map<String, Object?>;
final String body = v['body']! as String;
final String secret = v['secret']! as String;
final int timestamp = v['timestamp']! as int;

void main() {
  test('verifies the v1 signature produced by the server', () {
    final event = Webhook.constructEvent(body, {'X-Webhook-Signature': v['v1_signature']! as String}, secret);
    expect(event.eventType, WebhookEventType.chargeSuccess);
    expect(event.id, '4f6c2a8e-1b3d-4e5f-9a7b-0c1d2e3f4a5b');
    expect(event.objectId(), '9b2e5c1a-7d4f-4a3b-8c6e-1f2a3b4c5d6e');
    expect(event.reference(), 'CHG20261116ABCD');
    expect(event.amount(), 5000);
    expect(event.status(), 'SUCCESSFUL');
    expect(event.isCharge, isTrue);
  });

  test('signs exactly like the server (cross-SDK vector)', () {
    expect(V1SignatureVerifier.sign(utf8.encode(body), secret), v['v1_signature']);
    expect(V2SignatureVerifier.sign(utf8.encode(body), secret, timestamp), v['v2_signature']);
  });

  test('verifies v2 within the tolerance and rejects replays', () {
    final headers = {
      'x-webhook-signature-v2': v['v2_signature']! as String,
      'x-webhook-timestamp': '$timestamp',
    };
    final fresh = Webhook(secret, verifiers: [V2SignatureVerifier(clock: () => timestamp + 10)]);
    expect(fresh.parse(utf8.encode(body), headers).type, 'charge.success');

    final late = Webhook(secret, verifiers: [V2SignatureVerifier(clock: () => timestamp + 301)]);
    expect(() => late.parse(body, headers), throwsA(isA<SignatureVerificationException>()));
  });

  test('v2 wins over v1: a bad v2 cannot be bypassed with a valid v1', () {
    expect(
      () => Webhook.constructEvent(
          body,
          {
            'x-webhook-signature': v['v1_signature']! as String,
            'x-webhook-signature-v2': 'bad',
            'x-webhook-timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          },
          secret),
      throwsA(isA<SignatureVerificationException>()),
    );
  });

  test('rejects tampered bodies, wrong secrets and missing headers', () {
    final signed = {'x-webhook-signature': v['v1_signature']! as String};
    expect(() => Webhook.constructEvent('$body ', signed, secret), throwsA(isA<SignatureVerificationException>()));
    expect(() => Webhook.constructEvent(body, signed, 'other'), throwsA(isA<SignatureVerificationException>()));
    expect(() => Webhook.constructEvent(body, const {}, secret), throwsA(isA<SignatureVerificationException>()));
    expect(() => Webhook.constructEvent(<String, Object?>{}, signed, secret),
        throwsA(isA<SignatureVerificationException>()));
    expect(() => Webhook('', toleranceSeconds: 1), throwsA(isA<InvalidArgumentException>()));
  });

  group('WebhookProcessor', () {
    test('runs listeners, then replies 200', () async {
      final seen = <String>[];
      final process = WebhookProcessor(
        secret: 'whsec_test',
        dispatcher: EventDispatcher()
          ..on(WebhookEventType.chargeSuccess, (e) => seen.add('success:${e.objectId()}'))
          ..onAny((e) => seen.add('any:${e.type}')),
      );
      final hook = WebhookSigner.event('charge.success', {'charge': 'chg_1'}, 'whsec_test');
      final result = await process(hook.body, hook.headers);
      expect(result.status, 200);
      expect(seen, ['success:chg_1', 'any:charge.success']);
    });

    test('400 for a bad signature, 200 for duplicates, 500 when a listener throws', () async {
      final hook = WebhookSigner.event('payout.failed', {'payout': 'po_1'}, 'whsec_test');

      final bad = await WebhookProcessor(secret: 'other')(hook.body, hook.headers);
      expect(bad.status, 400);

      final dup = await WebhookProcessor(secret: 'whsec_test', isDuplicate: (_) => true)(hook.body, hook.headers);
      expect(dup.body, {'received': true, 'duplicate': true});

      Object? reported;
      final failing = WebhookProcessor(
        secret: 'whsec_test',
        dispatcher: EventDispatcher()..onAny((_) => throw StateError('db down')),
        onError: (error, _, __) => reported = error,
      );
      final result = await failing(hook.body, hook.headers);
      expect(result.status, 500);
      expect(reported, isA<StateError>());
      expect(result.jsonBody, isNot(contains('db down')));
    });
  });
}

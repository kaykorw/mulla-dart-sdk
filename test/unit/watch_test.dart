import 'dart:async';
import 'dart:convert';

import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('parseSse', () {
    test('handles multi-line data, comments, event names and chunk boundaries', () async {
      final chunks = [': keep-alive\n', 'event: status\nda', 'ta: {"a":\ndata: 1}\nid: 7\n\n', 'data: last\n'];
      final events = await parseSse(Stream.fromIterable(chunks.map(utf8.encode))).toList();
      expect(events, hasLength(2));
      expect(events.first.event, 'status');
      expect(events.first.data, '{"a":\n1}');
      expect(events.first.id, '7');
      expect(events.last.data, 'last');
    });
  });

  group('checkout.watch', () {
    test('streams status changes over SSE, skips pings and duplicates, closes when final', () async {
      final (mulla, fake) = makePublicClient();
      fake.pushEvents([
        {'checkout': 'cs_1', 'charge': 'chg_1', 'status': 'PENDING', 'reference': 'R1'},
        {'type': 'ping'},
        {'checkout': 'cs_1', 'charge': 'chg_1', 'status': 'PENDING', 'reference': 'R1'},
        {'checkout': 'cs_1', 'charge': 'chg_1', 'status': 'SUCCESSFUL', 'reference': 'R1'},
      ], keepOpen: true);

      final updates = await mulla.checkout.watch('cs_1', 'tok', useServerSentEvents: true).toList();
      expect(updates.map((u) => u.status), [ChargeStatus.pending, ChargeStatus.successful]);
      expect(updates.last.isSuccessful, isTrue);
      final r = fake.lastRequest!;
      expect(r.url, 'https://mfs.kayko.dev/gateway/v1/checkout/cs_1/events?token=tok');
      expect(r.header('accept'), 'text/event-stream');
      expect(r.header('x-device-id'), isNotNull);
    });

    test('falls back to polling when the stream drops', () async {
      final (mulla, fake) = makePublicClient();
      fake
        ..pushEvents([
          {'checkout': 'cs_1', 'status': 'PENDING'},
        ])
        ..pushJson(MullaFixtures.checkoutSession(id: 'cs_1', status: 'FAILED'));

      final updates = await mulla.checkout
          .watch('cs_1', 'tok', useServerSentEvents: true, pollInterval: const Duration(milliseconds: 10))
          .toList();
      expect(updates.map((u) => u.status), [ChargeStatus.pending, ChargeStatus.failed]);
    });

    test('switches to polling when the stream goes silent', () async {
      final (mulla, fake) = makePublicClient();
      final silent = StreamController<Map<String, Object?>>();
      addTearDown(silent.close);
      fake
        ..pushEventController(silent)
        ..pushJson(MullaFixtures.checkoutSession(id: 'cs_1', status: 'SUCCESSFUL'));
      silent.add({'checkout': 'cs_1', 'status': 'PENDING'});

      final updates = await mulla.checkout
          .watchUpdates<CheckoutUpdate>(
            path: 'checkout/cs_1/events',
            query: {'token': 'tok'},
            parse: CheckoutUpdate.new,
            isFinal: (u) => u.isFinal,
            statusOf: (u) => u.raw['status']?.toString(),
            poll: () async => CheckoutUpdate.fromSession(await mulla.checkout.retrieve('cs_1', 'tok')),
            pollInterval: const Duration(milliseconds: 10),
            useServerSentEvents: true,
            idleTimeout: const Duration(milliseconds: 50),
          )
          .toList()
          .timeout(const Duration(seconds: 5));
      expect(updates.map((u) => u.status), [ChargeStatus.pending, ChargeStatus.successful]);
      expect(silent.hasListener, isFalse, reason: 'the stalled connection is closed');
    });

    test('polls when SSE is off (web)', () async {
      final (mulla, fake) = makePublicClient();
      fake
        ..pushJson(MullaFixtures.checkoutSession(status: 'PENDING'))
        ..pushJson(MullaFixtures.checkoutSession(status: 'PENDING'))
        ..pushJson(MullaFixtures.checkoutSession(status: 'EXPIRED'));

      final updates = await mulla.checkout
          .watch('cs_test_1', 'tok', useServerSentEvents: false, pollInterval: const Duration(milliseconds: 5))
          .toList();
      expect(updates.map((u) => u.status), [ChargeStatus.pending, ChargeStatus.expired]);
    });

    test('a 4xx when opening the stream is reported, not retried forever', () async {
      final (mulla, fake) = makePublicClient();
      fake.pushStreamError(NotFoundException('[CHECKOUT_NOT_FOUND] nope', statusCode: 404));
      await expectLater(
        mulla.checkout.watch('cs_1', 'bad', useServerSentEvents: true).toList(),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('cancelling the subscription closes the stream', () async {
      final (mulla, fake) = makePublicClient();
      final controller = StreamController<Map<String, Object?>>();
      fake.pushEventController(controller);
      final first = Completer<CheckoutUpdate>();
      final sub = mulla.checkout.watch('cs_1', 'tok', useServerSentEvents: true).listen(first.complete);
      controller.add({'checkout': 'cs_1', 'status': 'PENDING'});
      expect((await first.future).status, ChargeStatus.pending);
      await sub.cancel();
      expect(controller.hasListener, isFalse);
      await controller.close();
    });
  });

  test('invoices.watch on the public client', () async {
    final (mulla, fake) = makePublicClient();
    fake.pushEvents([
      {'invoice': 'inv_1', 'status': 'ISSUED', 'payment_status': 'PENDING', 'amount_paid': 0, 'total_amount': 100},
      {'invoice': 'inv_1', 'status': 'PAID', 'payment_status': 'SUCCESSFUL', 'amount_paid': 100, 'total_amount': 100},
    ]);
    final updates = await mulla.invoices.watch('inv_1', useServerSentEvents: true).toList();
    expect(updates.last.isPaid, isTrue);
    expect(updates.first.paymentStatus, PaymentStatus.pending);
    expect(fake.lastRequest!.url, endsWith('/invoice/inv_1/events'));
  });
}

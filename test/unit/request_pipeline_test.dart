import 'dart:async';

import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  setUp(sleeps.clear);

  group('headers', () {
    test('adds auth, device, platform and idempotency headers', () async {
      final (mulla, fake) = makeClient();
      fake.pushJson({'id': 'chg_1', 'status': 'PENDING'});
      await mulla.charges
          .initiate(const InitiateChargeParams(provider: Provider.mtnRw, amount: 5000, phoneNumber: '0788 000 000'));

      final r = fake.lastRequest!;
      expect(r.method, 'POST');
      expect(r.url, 'https://mfs.kayko.dev/gateway/v1/charges/initiate');
      expect(r.header('x-api-key'), testKey);
      expect(r.header('x-platform'), startsWith('mulla-dart/'));
      expect(r.header('user-agent'), startsWith('mulla-dart/'));
      expect(r.header('x-device-id'), mulla.config.deviceId);
      expect(r.header('content-type'), 'application/json');
      expect(isUuidV4(r.header('x-idempotency-key')!), isTrue);
      expect(fake.lastBody, {'provider': 'MTN_RW', 'amount': 5000, 'phone_number': '+250788000000'});
    });

    test('GET requests carry no idempotency key and no content type', () async {
      final (mulla, fake) = makeClient();
      fake.pushJson({'id': 'chg_1'});
      await mulla.charges.retrieve('chg_1');
      expect(fake.lastRequest!.hasHeader('x-idempotency-key'), isFalse);
      expect(fake.lastRequest!.hasHeader('content-type'), isFalse);
    });

    test('per-request options set idempotency key, language and headers', () async {
      final (mulla, fake) = makeClient();
      final key = uuidV4();
      fake.pushJson({'id': 'chg_1'});
      await mulla.charges.initiate(
        const InitiateChargeParams(provider: Provider.airtelRw, amount: 100, phoneNumber: '+250730000000'),
        RequestOptions(idempotencyKey: key, lang: Language.rw, headers: const {'X-Trace': 't1'}),
      );
      final r = fake.lastRequest!;
      expect(r.header('x-idempotency-key'), key);
      expect(r.header('x-lang'), 'rw');
      expect(r.header('x-trace'), 't1');
    });

    test('a non-UUID idempotency key is rejected before sending', () async {
      final (mulla, fake) = makeClient();
      await expectLater(
        mulla.charges.retrieve('chg_1', const RequestOptions(idempotencyKey: 'order-1')),
        throwsA(isA<InvalidArgumentException>()),
      );
      fake.assertNothingSent();
    });

    test('header injection is impossible', () {
      expect(() => Request(method: 'GET', url: 'https://x', headers: const {'x-a': 'v\r\nx-b: 1'}),
          throwsA(isA<InvalidArgumentException>()));
    });
  });

  group('retries', () {
    test('reads are retried on 503 and network errors, reusing nothing unsafe', () async {
      final (mulla, fake) = makeClient();
      fake
        ..pushError(503, 'UNAVAILABLE')
        ..pushConnectionError(requestMayHaveBeenSent: true)
        ..pushJson({'id': 'chg_1', 'status': 'SUCCESSFUL'});
      final charge = await mulla.charges.retrieve('chg_1');
      expect(charge.isSuccessful, isTrue);
      fake.assertSentCount(3);
      expect(sleeps, hasLength(2));
    });

    test('writes are not retried after a 500 or a maybe-sent network error', () async {
      final (mulla, fake) = makeClient();
      fake.pushError(500, 'INTERNAL');
      await expectLater(
        mulla.payouts.initiate(const CreatePayoutParams(
            provider: Provider.mtnRw, amount: 1000, phoneNumber: '0788000000', reason: 'Refund')),
        throwsA(isA<ApiServerException>()),
      );
      fake.assertSentCount(1);

      final (mulla2, fake2) = makeClient();
      fake2.pushConnectionError(requestMayHaveBeenSent: true);
      await expectLater(
        mulla2.charges
            .initiate(const InitiateChargeParams(provider: Provider.mtnRw, amount: 1000, phoneNumber: '0788000000')),
        throwsA(isA<ConnectionException>()),
      );
      fake2.assertSentCount(1);
    });

    test('writes are retried on 429/503 and when the connection never opened, with the same key', () async {
      final (mulla, fake) = makeClient();
      fake
        ..pushError(429, 'RATE_LIMITED')
        ..pushConnectionError(requestMayHaveBeenSent: false)
        ..pushJson({'id': 'chg_1'});
      await mulla.charges
          .initiate(const InitiateChargeParams(provider: Provider.mtnRw, amount: 1000, phoneNumber: '0788000000'));
      final keys = fake.requests.map((r) => r.header('x-idempotency-key')).toSet();
      expect(fake.requests, hasLength(3));
      expect(keys, hasLength(1));
    });

    test('Retry-After is honoured, but not beyond the maximum delay', () async {
      final (mulla, fake) = makeClient();
      fake
        ..pushJson({'message': 'slow down'}, status: 429, headers: {'retry-after': '2'})
        ..pushJson({'id': 'chg_1'});
      await mulla.charges.retrieve('chg_1');
      expect(sleeps.single, const Duration(seconds: 2));

      final (mulla2, fake2) = makeClient();
      fake2.pushJson({'message': 'slow down'}, status: 429, headers: {'retry-after': '60'});
      await expectLater(mulla2.charges.retrieve('chg_1'),
          throwsA(isA<RateLimitException>().having((e) => e.retryAfter, 'retryAfter', 60)));
    });

    test('maxRetries: 0 turns retries off', () async {
      final (mulla, fake) = makeClient(maxRetries: 0);
      fake.pushError(503, 'UNAVAILABLE');
      await expectLater(mulla.charges.retrieve('chg_1'), throwsA(isA<ApiServerException>()));
      fake.assertSentCount(1);
    });

    test('backoff grows and is capped', () {
      final b = ExponentialBackoff(jitter: false);
      expect(b.delay(1, null), const Duration(milliseconds: 500));
      expect(b.delay(2, null), const Duration(seconds: 1));
      expect(b.delay(10, null), const Duration(seconds: 8));
    });
  });

  group('middleware and logging', () {
    test('custom middleware runs and can add headers', () async {
      final fake = FakeTransport()..pushJson({'id': 'c'});
      final mulla = MullaClient(
        apiKey: testKey,
        transport: fake,
        middleware: [Middleware.fn((request, next) => next(request.withHeader('x-trace-id', 'abc')))],
      );
      await mulla.charges.retrieve('c');
      expect(fake.lastRequest!.header('x-trace-id'), 'abc');
    });

    test('the logger never receives the key or checkout tokens, and a throwing logger is ignored', () async {
      final lines = <String>[];
      final (mulla, fake) = makeClient(logger: (level, message, context) {
        lines.add('$level $message $context');
        throw StateError('logger broke');
      });
      fake.pushJson({'id': 'cs_1'});
      await mulla.checkout.retrieve('cs_1', 'very-secret-token');
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains(testKey)));
      expect(lines.single, isNot(contains('very-secret-token')));
      expect(lines.single, contains('token=***'));
    });
  });

  test('a cancelled request is not retried', () async {
    final (mulla, fake) = makeClient();
    fake.push(RequestCancelledException('cancelled'));
    final abort = Completer<void>()..complete();
    await expectLater(
      mulla.charges.retrieve('chg_1', RequestOptions(abortTrigger: abort.future)),
      throwsA(isA<RequestCancelledException>()),
    );
    fake.assertSentCount(1);
  });
}

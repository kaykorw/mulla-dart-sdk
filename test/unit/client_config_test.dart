import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('MullaClient configuration', () {
    test('the key prefix picks the official server', () {
      expect(MullaClient(apiKey: testKey).baseUrl, 'https://mfs.kayko.dev/gateway/v1');
      expect(MullaClient(apiKey: liveKey).baseUrl, 'https://core.mulla.app/gateway/v1');
      expect(MullaClient(apiKey: liveKey).isLive, isTrue);
    });

    test('a missing or blank key fails with a helpful message', () {
      for (final key in [null, '', '   ']) {
        expect(
          () => MullaClient(apiKey: key),
          throwsA(isA<InvalidArgumentException>().having((e) => e.message, 'message', contains('Missing "apiKey"'))),
        );
      }
    });

    test('a malformed key is rejected', () {
      expect(() => MullaClient(apiKey: 'pk_test_abc_def'), throwsA(isA<InvalidArgumentException>()));
    });

    test('the environment guard rejects a key from the other environment', () {
      expect(
        () => MullaClient(apiKey: testKey, environment: Environment.production),
        throwsA(isA<InvalidArgumentException>().having((e) => e.message, 'message', contains('test (sk_test_)'))),
      );
      expect(MullaClient(apiKey: testKey, environment: Environment.test).environment, Environment.test);
    });

    test('base URLs must be https except for local hosts, and get /v1', () {
      expect(
          MullaClient(apiKey: testKey, baseUrl: 'https://x.example/gateway/').baseUrl, 'https://x.example/gateway/v1');
      expect(MullaClient(apiKey: testKey, baseUrl: 'http://localhost:3000/v2').baseUrl, 'http://localhost:3000/v2');
      expect(MullaClient(apiKey: testKey, baseUrl: 'http://10.0.2.2:3000').baseUrl, 'http://10.0.2.2:3000/v1');
      expect(
          () => MullaClient(apiKey: testKey, baseUrl: 'http://evil.example'), throwsA(isA<InvalidArgumentException>()));
      expect(() => MullaClient(apiKey: testKey, baseUrl: 'https://u:p@x.example'),
          throwsA(isA<InvalidArgumentException>()));
      expect(MullaClient(apiKey: testKey, baseUrl: '  ').baseUrl, 'https://mfs.kayko.dev/gateway/v1');
    });

    test('conflicting options fail at construction', () {
      expect(() => MullaClient(apiKey: testKey, maxRetries: 1, retryStrategy: ExponentialBackoff()),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => MullaClient(apiKey: testKey, timeout: Duration.zero), throwsA(isA<InvalidArgumentException>()));
      expect(() => MullaClient(apiKey: testKey, deviceId: 'nope'), throwsA(isA<InvalidArgumentException>()));
      expect(() => MullaClient(apiKey: testKey, webhookUrl: 'http://shop.example/hook'),
          throwsA(isA<InvalidArgumentException>()));
      expect(() => MullaClient(apiKey: testKey, appInfo: const AppInfo(name: 'my shop')),
          throwsA(isA<InvalidArgumentException>()));
    });

    test('the device id is stable per key and matches the other SDKs', () {
      final a = MullaClient(apiKey: testKey).config.deviceId;
      expect(a, MullaClient(apiKey: testKey).config.deviceId);
      expect(isUuidV4(a), isTrue);
      expect(a, uuidFromSeed('mulla-dart:abc123'));
    });

    test('toString never shows secrets', () {
      final client = MullaClient(apiKey: testKey, webhookSecret: 'whsec_super');
      expect('$client', isNot(contains('secretvalue')));
      expect('${client.config}', isNot(contains('secretvalue')));
      expect('${client.config}', isNot(contains('whsec_super')));
      expect(client.config.maskedApiKey(), 'sk_test_abc123_****');
    });

    test('webhooks() uses the configured secret or asks for one', () {
      expect(MullaClient(apiKey: testKey, webhookSecret: 'whsec').webhooks(), isA<Webhook>());
      expect(() => MullaClient(apiKey: testKey).webhooks(), throwsA(isA<InvalidArgumentException>()));
    });
  });

  group('MullaPublicClient', () {
    test('needs no key and sends no x-api-key', () async {
      final fake = FakeTransport()..pushJson(MullaFixtures.checkoutSession());
      final client = MullaPublicClient(environment: Environment.test, transport: fake);
      await client.checkout.retrieve('cs_1', 'tok');

      expect(fake.lastRequest!.hasHeader('x-api-key'), isFalse);
      expect(fake.lastRequest!.url, 'https://mfs.kayko.dev/gateway/v1/checkout/cs_1?token=tok');
      expect(client.config.isPublic, isTrue);
    });

    test('MullaClient refuses a public config', () {
      expect(() => MullaClient.fromConfig(MullaConfig.public(environment: Environment.test)),
          throwsA(isA<InvalidArgumentException>()));
    });
  });
}

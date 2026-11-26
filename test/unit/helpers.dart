import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';

const testKey = 'sk_test_abc123_secretvalue';
const liveKey = 'sk_live_abc123_secretvalue';

final List<Duration> sleeps = [];

Future<void> noSleep(Duration d) async => sleeps.add(d);

(MullaClient, FakeTransport) makeClient({int? maxRetries, MullaLogger? logger, String? webhookSecret}) {
  final fake = FakeTransport();
  final client = MullaClient(
    apiKey: testKey,
    transport: fake,
    sleep: noSleep,
    maxRetries: maxRetries,
    logger: logger,
    webhookSecret: webhookSecret,
  );

  return (client, fake);
}

(MullaPublicClient, FakeTransport) makePublicClient() {
  final fake = FakeTransport();

  return (MullaPublicClient(environment: Environment.test, transport: fake, sleep: noSleep), fake);
}

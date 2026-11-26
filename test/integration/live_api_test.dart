// Runs against the sandbox only when MULLA_SECRET_KEY is a test key:
//   MULLA_SECRET_KEY=sk_test_... dart test test/integration
@Tags(['integration'])
library;

import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';
import 'package:test/test.dart';

void main() {
  final key = Platform.environment['MULLA_SECRET_KEY'];
  final baseUrl = Platform.environment['MULLA_BASE_URL'];
  final skip = key == null || !key.startsWith('sk_test_') ? 'Set MULLA_SECRET_KEY=sk_test_... to run' : null;

  test('lists charges', () async {
    final mulla = MullaClient(apiKey: key, baseUrl: baseUrl);
    final page = await mulla.charges.list(const ChargeListFilters(limit: 1));
    expect(page.page, greaterThanOrEqualTo(1));
  }, skip: skip);

  test('creates a checkout session and reads it with the public client', () async {
    final mulla = MullaClient(apiKey: key, baseUrl: baseUrl);
    final session = await mulla.charges.createCheckout(const CreateCheckoutParams(
      amount: 100,
      reason: 'SDK integration test',
      successUrl: 'https://example.com/ok',
      cancelUrl: 'https://example.com/no',
    ));

    final public = MullaPublicClient(environment: Environment.test, baseUrl: baseUrl);
    final read = await public.checkout.retrieve(session.id, session.token!);
    expect(read.id, session.id);
    expect(read.status, ChargeStatus.pending);

    final first = await public.checkout.watch(session.id, session.token!).first;
    expect(first.status, ChargeStatus.pending);
  }, skip: skip);
}

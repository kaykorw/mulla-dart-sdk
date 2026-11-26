import 'package:mulla_dart/mulla_dart.dart';
import 'package:mulla_dart/testing.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  setUp(sleeps.clear);

  test('charges.createCheckout maps camelCase params to the API body', () async {
    final (mulla, fake) = makeClient();
    fake.pushJson({
      'id': 'cs_1',
      'token': 'tok',
      'checkout_url': 'https://pay',
      'charge': {'id': 'chg_1'}
    });
    final session = await mulla.charges.createCheckout(const CreateCheckoutParams(
      amount: 25000,
      reason: 'Order #1001',
      successUrl: 'https://shop/thanks',
      cancelUrl: 'https://shop/cart',
      metadata: {'orderId': 1001},
      customer: 'cus_1',
    ));
    expect(fake.lastBody, {
      'amount': 25000,
      'success_url': 'https://shop/thanks',
      'cancel_url': 'https://shop/cart',
      'reason': 'Order #1001',
      'metadata': {'orderId': 1001},
      'customer': {'id': 'cus_1'},
    });
    expect(session.charge, 'chg_1');
    expect(session.token, 'tok');
  });

  test('models are typed, keep raw data, and map unknown enums to null', () async {
    final (mulla, fake) = makeClient();
    fake.pushJson({
      'id': 'chg_1',
      'status': 'BRAND_NEW_STATUS',
      'provider': 'MTN_RW',
      'amount': '5000',
      'created_at': '2026-11-20T10:00:00.000Z',
      'extra': 'x',
    });
    final charge = await mulla.charges.retrieve('chg_1');
    expect(charge.status, isNull);
    expect(charge.provider, Provider.mtnRw);
    expect(charge.amount, 5000);
    expect(charge.createdAt, DateTime.utc(2026, 11, 20, 10));
    expect(charge.get('extra'), 'x');
    expect(charge.raw['status'], 'BRAND_NEW_STATUS');
  });

  test('ids are validated and encoded', () async {
    final (mulla, fake) = makeClient();
    await expectLater(mulla.charges.retrieve(' '), throwsA(isA<InvalidArgumentException>()));
    await expectLater(mulla.charges.retrieve('..'), throwsA(isA<InvalidArgumentException>()));
    fake.pushJson({'id': 'a/b'});
    await mulla.charges.retrieve('a/b');
    expect(fake.lastRequest!.url, endsWith('/charges/a%2Fb'));
  });

  test('list filters become a query and pages iterate', () async {
    final (mulla, fake) = makeClient();
    fake
      ..pushJson({
        'data': [
          {'id': 'c1'},
          {'id': 'c2'},
        ],
        'total': 3,
        'page': 1,
        'limit': 2,
        'total_pages': 2,
      })
      ..pushJson({
        'data': [
          {'id': 'c3'},
        ],
        'total': 3,
        'page': 2,
        'limit': 2,
        'total_pages': 2,
      });
    final ids = await mulla.charges
        .list(ChargeListFilters(status: ChargeStatus.successful, limit: 2, startDate: DateTime.utc(2026, 11)))
        .autoPaging()
        .map((c) => c.id)
        .toList();
    expect(ids, ['c1', 'c2', 'c3']);
    expect(fake.requests.first.url,
        'https://mfs.kayko.dev/gateway/v1/charges?limit=2&status=SUCCESSFUL&start_date=2026-11-01T00%3A00%3A00.000Z');
    expect(fake.requests.last.url, contains('page=2'));
  });

  test('a single page reports hasMore and nextPage', () async {
    final (mulla, fake) = makeClient();
    fake.pushJson({
      'data': [
        {'id': 'p1'}
      ],
      'total': 1,
      'page': 1,
      'limit': 20,
      'total_pages': 1
    });
    final page = await mulla.payouts.list();
    expect(page.hasMore, isFalse);
    expect(await page.nextPage(), isNull);
    expect(page.first!.id, 'p1');
  });

  test('waitForFinalStatus polls until final', () async {
    final (mulla, fake) = makeClient();
    fake
      ..pushJson({'id': 'chg_1', 'status': 'PENDING'})
      ..pushJson({'id': 'chg_1', 'status': 'SUCCESSFUL'});
    final charge = await mulla.charges.waitForFinalStatus('chg_1', interval: const Duration(seconds: 1));
    expect(charge.isSuccessful, isTrue);
    expect(sleeps, [const Duration(seconds: 1)]);
    await expectLater(
        mulla.charges.waitForFinalStatus('chg_1', interval: Duration.zero), throwsA(isA<InvalidArgumentException>()));
  });

  test('invoices: create, pay and update status', () async {
    final (mulla, fake) = makeClient();
    fake
      ..pushJson({
        'id': 'inv_1',
        'items': [
          {'name': 'A', 'unit_price': 10}
        ]
      })
      ..pushJson({
        'payment': {'id': 'pay_1', 'status': 'PENDING'},
        'message': 'Approve on your phone'
      })
      ..pushJson({'id': 'inv_1', 'status': 'CANCELLED'});
    final invoice = await mulla.invoices.create(CreateInvoiceParams(
      customer: 'cus_1',
      items: const [InvoiceItemParams(name: 'A', unitPrice: 10, quantity: 2)],
      dueDate: DateTime.utc(2026, 12, 31),
    ));
    expect(invoice.items.single.name, 'A');
    expect((fake.lastBody! as Map)['due_date'], '2026-12-31T00:00:00.000Z');

    final payment =
        await mulla.invoices.pay('inv_1', const PayInvoiceParams(provider: Provider.mtnRw, phoneNumber: '788000000'));
    expect(payment.payment!.status, PaymentStatus.pending);
    expect(fake.lastRequest!.url, endsWith('/invoice/inv_1/pay'));
    expect(fake.lastBody, {'provider': 'MTN_RW', 'phone_number': '+250788000000'});

    final cancelled = await mulla.invoices.updateStatus('inv_1', InvoiceStatus.cancelled);
    expect(cancelled.isFinal, isTrue);
    expect(fake.lastRequest!.method, 'PATCH');
    expect(fake.lastBody, {'status': 'CANCELLED'});
  });

  test('webhookEndpoint.create uses the configured URL and defaults to active', () async {
    final fake = FakeTransport();
    final mulla = MullaClient(apiKey: testKey, transport: fake, webhookUrl: 'https://shop.example/hook');
    fake.pushJson({'id': 'we_1', 'secret': 'whsec_1'});
    final endpoint = await mulla.webhookEndpoint.create();
    expect(fake.lastBody, {'url': 'https://shop.example/hook', 'is_active': true});
    expect('$endpoint', isNot(contains('whsec_1')));
    expect(() => makeClient().$1.webhookEndpoint.create(), throwsA(isA<InvalidArgumentException>()));
  });

  test('bank branches need a code or swift', () async {
    final (mulla, _) = makeClient();
    await expectLater(
        mulla.referenceData.bankBranches(const BankBranchFilters()), throwsA(isA<InvalidArgumentException>()));
  });

  test('params are validated before sending', () {
    expect(() => const InitiateChargeParams(provider: Provider.mtnRw, amount: 0, phoneNumber: '0788000000').toApi(),
        throwsA(isA<InvalidArgumentException>()));
    expect(
        () => const CreatePayoutParams(provider: Provider.mtnRw, amount: 10, phoneNumber: '078', reason: ' ').toApi(),
        throwsA(isA<InvalidArgumentException>()));
  });

  group('phone numbers', () {
    test('normalizePhoneNumber matches the other SDKs', () {
      expect(normalizePhoneNumber('0788 000 000'), '+250788000000');
      expect(normalizePhoneNumber('250788000000'), '+250788000000');
      expect(normalizePhoneNumber('788000000'), '+250788000000');
      expect(normalizePhoneNumber('+256 (700) 000-000'), '+256700000000');
      expect(normalizePhoneNumber(' 12345 '), '12345');
    });

    test('drops a 0 typed after the country code', () {
      expect(normalizePhoneNumber('+250 0788 000 000'), '+250788000000');
      expect(normalizePhoneNumber('2500788000000'), '+250788000000');
      expect(normalizePhoneNumber('+250788000000'), '+250788000000');
      expect(isRwandanMobileNumber('+2500721234567'), isTrue);
      expect(providerForPhoneNumber('+250 0730 000 000'), Provider.airtelRw);
    });

    test('provider guessing and validation', () {
      expect(providerForPhoneNumber('0788000000'), Provider.mtnRw);
      expect(providerForPhoneNumber('0730000000'), Provider.airtelRw);
      expect(providerForPhoneNumber('0700000000'), isNull);
      expect(isRwandanMobileNumber('0721234567'), isTrue);
      expect(isRwandanMobileNumber('078'), isFalse);
    });
  });
}

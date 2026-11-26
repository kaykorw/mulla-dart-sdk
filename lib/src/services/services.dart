import '../enums.dart';
import '../errors.dart';
import '../http/request_options.dart';
import '../models/collection.dart';
import '../models/model.dart';
import '../models/models.dart';
import '../params.dart';
import '../support/normalizer.dart';
import 'base.dart';

typedef _Id = AbstractService;

class ChargeService extends AbstractService {
  ChargeService(super.requestor);

  @override
  String get resource => 'charges';

  @override
  ApiScope get scope => ApiScope.charges;

  /// Sends a payment prompt to the customer's phone. The charge starts as `PENDING`.
  Future<Charge> initiate(InitiateChargeParams params, [RequestOptions? options]) async =>
      send(Charge.new, 'Charge', 'POST', 'charges/initiate', body: params.toApi(), options: options);

  /// Creates a hosted checkout session. Send the customer to `session.checkoutUrl`,
  /// or hand `session.id` and `session.token` to your app (mulla_flutter).
  Future<CheckoutSession> createCheckout(CreateCheckoutParams params, [RequestOptions? options]) async =>
      send(CheckoutSession.new, 'CheckoutSession', 'POST', 'charges/checkout', body: params.toApi(), options: options);

  Future<Charge> retrieve(String id, [RequestOptions? options]) async =>
      send(Charge.new, 'Charge', 'GET', 'charges/${_Id.id(id, 'charge id')}', options: options);

  Future<Collection<Charge>> list([ChargeListFilters? filters, RequestOptions? options]) async =>
      listModels(Charge.new, 'charges', filters, options);

  /// Polls until the charge is final or [timeout] passes; returns the latest state either way.
  Future<Charge> waitForFinalStatus(
    String id, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 5),
  }) async =>
      pollUntilFinal(() => retrieve(id), (c) => c.isFinal, timeout: timeout, interval: interval);
}

/// Public checkout endpoints: authorised by the session token, no secret key needed.
class CheckoutService extends AbstractService {
  CheckoutService(super.requestor);

  @override
  String get resource => 'checkout';

  Future<CheckoutSession> retrieve(String id, String token, [RequestOptions? options]) async =>
      send(CheckoutSession.new, 'CheckoutSession', 'GET', 'checkout/${_Id.id(id, 'checkout id')}',
          query: {'token': _token(token)}, options: options);

  /// Sends the payment prompt for this session to [params.phoneNumber].
  Future<CheckoutSession> pay(String id, String token, PayParams params, [RequestOptions? options]) async =>
      send(CheckoutSession.new, 'CheckoutSession', 'POST', 'checkout/${_Id.id(id, 'checkout id')}/pay',
          query: {'token': _token(token)}, body: params.toApi(), options: options);

  /// URL of the server-sent events stream for this session.
  String eventsUrl(String id, String token) =>
      '${config.baseUrl}/checkout/${_Id.id(id, 'checkout id')}/events?token=${encodeRfc3986(_token(token))}';

  /// Live status updates until the session is final. Uses server-sent events and falls back
  /// to polling every [pollInterval] when streaming is unavailable (web) or drops.
  Stream<CheckoutUpdate> watch(
    String id,
    String token, {
    Duration pollInterval = const Duration(seconds: 3),
    bool? useServerSentEvents,
  }) =>
      watchUpdates(
        path: 'checkout/${_Id.id(id, 'checkout id')}/events',
        query: {'token': _token(token)},
        parse: CheckoutUpdate.new,
        isFinal: (u) => u.isFinal,
        statusOf: (u) => u.raw['status']?.toString(),
        poll: () async => CheckoutUpdate.fromSession(await retrieve(id, token)),
        pollInterval: pollInterval,
        useServerSentEvents: useServerSentEvents,
      );

  String _token(String token) {
    if (token.trim().isEmpty) {
      throw InvalidArgumentException('The checkout token cannot be empty. Use session.token from createCheckout().');
    }

    return token;
  }
}

class PayoutService extends AbstractService {
  PayoutService(super.requestor);

  @override
  String get resource => 'payouts';

  @override
  ApiScope get scope => ApiScope.payouts;

  Future<Payout> initiate(CreatePayoutParams params, [RequestOptions? options]) async =>
      send(Payout.new, 'Payout', 'POST', 'payouts/initiate', body: params.toApi(), options: options);

  Future<Payout> retrieve(String id, [RequestOptions? options]) async =>
      send(Payout.new, 'Payout', 'GET', 'payouts/${_Id.id(id, 'payout id')}', options: options);

  Future<Collection<Payout>> list([PayoutListFilters? filters, RequestOptions? options]) async =>
      listModels(Payout.new, 'payouts', filters, options);

  Future<Payout> waitForFinalStatus(
    String id, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 5),
  }) async =>
      pollUntilFinal(() => retrieve(id), (p) => p.isFinal, timeout: timeout, interval: interval);
}

class RechargeService extends AbstractService {
  RechargeService(super.requestor);

  @override
  String get resource => 'recharges';

  @override
  ApiScope get scope => ApiScope.recharges;

  Future<Recharge> initiate(InitiateRechargeParams params, [RequestOptions? options]) async =>
      send(Recharge.new, 'Recharge', 'POST', 'recharge/initiate', body: params.toApi(), options: options);

  Future<Recharge> retrieve(String id, [RequestOptions? options]) async =>
      send(Recharge.new, 'Recharge', 'GET', 'recharge/${_Id.id(id, 'recharge id')}', options: options);

  Future<Collection<Recharge>> list([RechargeListFilters? filters, RequestOptions? options]) async =>
      listModels(Recharge.new, 'recharge', filters, options);

  Future<Recharge> waitForFinalStatus(
    String id, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 5),
  }) async =>
      pollUntilFinal(() => retrieve(id), (r) => r.isFinal, timeout: timeout, interval: interval);
}

/// Invoices. `retrievePublic`, `pay`, `eventsUrl` and `watch` use public endpoints and
/// also work on [MullaPublicClient].
class InvoiceService extends AbstractService {
  InvoiceService(super.requestor);

  @override
  String get resource => 'invoices';

  @override
  ApiScope get scope => ApiScope.invoices;

  Future<Invoice> create(CreateInvoiceParams params, [RequestOptions? options]) async =>
      send(Invoice.new, 'Invoice', 'POST', 'invoices', body: params.toApi(), options: options);

  Future<Invoice> retrieve(String id, [RequestOptions? options]) async =>
      send(Invoice.new, 'Invoice', 'GET', 'invoices/${_Id.id(id, 'invoice id')}', options: options);

  Future<Collection<Invoice>> list([InvoiceListFilters? filters, RequestOptions? options]) async =>
      listModels(Invoice.new, 'invoices', filters, options);

  Future<Invoice> update(String id, UpdateInvoiceParams params, [RequestOptions? options]) async =>
      send(Invoice.new, 'Invoice', 'PATCH', 'invoices/${_Id.id(id, 'invoice id')}',
          body: params.toApi(), options: options);

  Future<Invoice> updateStatus(String id, InvoiceStatus status, [RequestOptions? options]) async =>
      send(Invoice.new, 'Invoice', 'PATCH', 'invoices/${_Id.id(id, 'invoice id')}/status',
          body: {'status': status}, options: options);

  Future<Collection<PaymentTransaction>> listPayments(String id, [RequestOptions? options]) async =>
      listModels(PaymentTransaction.new, 'invoices/${_Id.id(id, 'invoice id')}/payments', null, options);

  Future<PaymentTransaction> retrievePayment(String id, String transactionId, [RequestOptions? options]) async => send(
      PaymentTransaction.new,
      'PaymentTransaction',
      'GET',
      'invoices/${_Id.id(id, 'invoice id')}/payments/${_Id.id(transactionId, 'transaction id')}',
      options: options);

  /// The customer-facing view of an invoice (public endpoint).
  Future<Invoice> retrievePublic(String id, [RequestOptions? options]) async =>
      send(Invoice.new, 'Invoice', 'GET', 'invoice/${_Id.id(id, 'invoice id')}', options: options);

  /// Sends a payment prompt for this invoice to the customer's phone (public endpoint).
  Future<PaymentInitiation> pay(String id, PayInvoiceParams params, [RequestOptions? options]) async =>
      send(PaymentInitiation.new, 'PaymentInitiation', 'POST', 'invoice/${_Id.id(id, 'invoice id')}/pay',
          body: params.toApi(), options: options);

  String eventsUrl(String id) => '${config.baseUrl}/invoice/${_Id.id(id, 'invoice id')}/events';

  /// Live updates until the invoice is paid or cancelled (server-sent events, polling fallback).
  Stream<InvoiceUpdate> watch(
    String id, {
    Duration pollInterval = const Duration(seconds: 3),
    bool? useServerSentEvents,
  }) =>
      watchUpdates(
        path: 'invoice/${_Id.id(id, 'invoice id')}/events',
        parse: InvoiceUpdate.new,
        isFinal: (u) => u.isFinal,
        statusOf: (u) => '${u.raw['status']}/${u.raw['payment_status']}/${u.raw['amount_paid']}',
        poll: () async => InvoiceUpdate.fromInvoice(await retrievePublic(id)),
        pollInterval: pollInterval,
        useServerSentEvents: useServerSentEvents,
      );
}

class CustomerService extends AbstractService {
  CustomerService(super.requestor);

  @override
  String get resource => 'customers';

  @override
  ApiScope get scope => ApiScope.customers;

  Future<Customer> create(CustomerParams params, [RequestOptions? options]) async =>
      send(Customer.new, 'Customer', 'POST', 'customers', body: params.toApi(), options: options);

  Future<Customer> retrieve(String id, [RequestOptions? options]) async =>
      send(Customer.new, 'Customer', 'GET', 'customers/${_Id.id(id, 'customer id')}', options: options);

  Future<Collection<Customer>> list([CustomerListFilters? filters, RequestOptions? options]) async =>
      listModels(Customer.new, 'customers', filters, options);

  Future<Customer> update(String id, CustomerParams params, [RequestOptions? options]) async =>
      send(Customer.new, 'Customer', 'PATCH', 'customers/${_Id.id(id, 'customer id')}',
          body: params.toApi(), options: options);

  Future<MullaObject> blacklist(String id, [RequestOptions? options]) async =>
      send(MullaObject.new, 'MullaObject', 'PATCH', 'customers/${_Id.id(id, 'customer id')}/blacklist',
          body: const {}, options: options);

  Future<MullaObject> whitelist(String id, [RequestOptions? options]) async =>
      send(MullaObject.new, 'MullaObject', 'PATCH', 'customers/${_Id.id(id, 'customer id')}/whitelist',
          body: const {}, options: options);
}

class WebhookEndpointService extends AbstractService {
  WebhookEndpointService(super.requestor);

  @override
  String get resource => 'webhookEndpoint';

  /// Registers your webhook URL. Store the returned `endpoint.secret`: it is shown only once.
  Future<WebhookEndpoint> create(
      [CreateWebhookEndpointParams params = const CreateWebhookEndpointParams(), RequestOptions? options]) async {
    final url = params.url ?? config.webhookUrl;
    if (url == null || url.trim().isEmpty) {
      throw InvalidArgumentException('webhookEndpoint.create() needs a url (or the client\'s "webhookUrl" option).');
    }

    return send(WebhookEndpoint.new, 'WebhookEndpoint', 'POST', 'webhooks',
        body: {...params.toApi(), 'url': url, 'is_active': params.isActive ?? true}, options: options);
  }

  Future<WebhookEndpoint> retrieve([RequestOptions? options]) async =>
      send(WebhookEndpoint.new, 'WebhookEndpoint', 'GET', 'webhooks', options: options);

  Future<WebhookEndpoint> update(UpdateWebhookEndpointParams changes, [RequestOptions? options]) async =>
      send(WebhookEndpoint.new, 'WebhookEndpoint', 'PATCH', 'webhooks', body: changes.toApi(), options: options);

  Future<WebhookEndpoint> rotateSecret([RequestOptions? options]) async =>
      send(WebhookEndpoint.new, 'WebhookEndpoint', 'POST', 'webhooks/rotate-secret', body: const {}, options: options);

  /// Asks Mulla to send a `webhook.test` event to your URL.
  Future<WebhookTestResult> test([RequestOptions? options]) async =>
      send(WebhookTestResult.new, 'WebhookTestResult', 'POST', 'webhooks/test', body: const {}, options: options);
}

class ReferenceDataService extends AbstractService {
  ReferenceDataService(super.requestor);

  @override
  String get resource => 'referenceData';

  Future<Collection<MullaObject>> banks(BankFilters filters, [RequestOptions? options]) async =>
      listModels(MullaObject.new, 'banks', filters, options);

  Future<Collection<MullaObject>> bankBranches(BankBranchFilters filters, [RequestOptions? options]) async =>
      listModels(MullaObject.new, 'banks/branches', filters, options);

  Future<Collection<MullaObject>> countries([CountryFilters? filters, RequestOptions? options]) async =>
      listModels(MullaObject.new, 'countries', filters, options);

  Future<Collection<MullaObject>> currencies([CurrencyFilters? filters, RequestOptions? options]) async =>
      listModels(MullaObject.new, 'currencies', filters, options);

  Future<Collection<MullaObject>> scopes([ScopeFilters? filters, RequestOptions? options]) async =>
      listModels(MullaObject.new, 'scopes', filters, options);
}

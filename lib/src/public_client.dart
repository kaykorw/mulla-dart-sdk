import 'package:http/http.dart' as http;

import 'config.dart';
import 'enums.dart';
import 'environment.dart';
import 'http/middleware.dart';
import 'http/request_options.dart';
import 'http/requestor.dart';
import 'http/retry.dart';
import 'http/transport.dart';
import 'models/models.dart';
import 'params.dart';
import 'services/services.dart';

/// Key-less client for apps and browsers. It only calls the public endpoints that a
/// checkout session token or an invoice id authorises, so it holds no secret.
///
/// Your backend creates the session with a secret-key SDK (`charges.createCheckout`) and
/// hands `session.id` + `session.token` to the app:
///
///     final mulla = MullaPublicClient(environment: Environment.test);
///     await mulla.checkout.pay(id, token, PayParams(provider: Provider.mtnRw, phoneNumber: '0788000000'));
///     await for (final update in mulla.checkout.watch(id, token)) { ... }
class MullaPublicClient {
  MullaPublicClient({
    required Environment environment,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 30),
    int? maxRetries,
    Language? lang,
    String? deviceId,
    AppInfo? appInfo,
    MullaLogger? logger,
    http.Client? httpClient,
    Transport? transport,
    List<Middleware> middleware = const [],
    RetryStrategy? retryStrategy,
    EnvironmentResolver? environmentResolver,
    Sleep? sleep,
  }) : this.fromConfig(MullaConfig.public(
          environment: environment,
          baseUrl: baseUrl,
          timeout: timeout,
          maxRetries: maxRetries,
          lang: lang,
          deviceId: deviceId,
          appInfo: appInfo,
          logger: logger,
          httpClient: httpClient,
          transport: transport,
          middleware: middleware,
          retryStrategy: retryStrategy,
          environmentResolver: environmentResolver,
          sleep: sleep,
        ));

  MullaPublicClient.fromConfig(this.config) : _requestor = ApiRequestor(config);

  final MullaConfig config;
  final ApiRequestor _requestor;

  /// Hosted checkout sessions: `retrieve`, `pay`, `watch`, `eventsUrl`.
  late final CheckoutService checkout = CheckoutService(_requestor);

  /// Customer-facing invoice endpoints: `retrievePublic`, `pay`, `watch`, `eventsUrl`.
  late final PublicInvoiceService invoices = PublicInvoiceService(InvoiceService(_requestor));

  Environment get environment => config.environment;

  String get baseUrl => config.baseUrl;

  @override
  String toString() => 'MullaPublicClient(environment: ${environment.value}, baseUrl: $baseUrl)';
}

/// The public subset of [InvoiceService] (the rest needs a secret key).
class PublicInvoiceService {
  PublicInvoiceService(this._invoices);

  final InvoiceService _invoices;

  Future<Invoice> retrievePublic(String id, [RequestOptions? options]) => _invoices.retrievePublic(id, options);

  Future<PaymentInitiation> pay(String id, PayInvoiceParams params, [RequestOptions? options]) =>
      _invoices.pay(id, params, options);

  String eventsUrl(String id) => _invoices.eventsUrl(id);

  Stream<InvoiceUpdate> watch(String id,
          {Duration pollInterval = const Duration(seconds: 3), bool? useServerSentEvents}) =>
      _invoices.watch(id, pollInterval: pollInterval, useServerSentEvents: useServerSentEvents);
}

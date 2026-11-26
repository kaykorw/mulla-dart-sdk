import 'package:http/http.dart' as http;

import 'config.dart';
import 'enums.dart';
import 'environment.dart';
import 'errors.dart';
import 'http/middleware.dart';
import 'http/requestor.dart';
import 'http/retry.dart';
import 'http/transport.dart';
import 'services/services.dart';
import 'webhooks/webhook.dart';

/// Entry point to the whole Mulla API, for servers only.
class MullaClient {
  /// The SDK never reads environment variables: pass every value explicitly.
  MullaClient({
    required String? apiKey,
    Environment? environment,
    String? baseUrl,
    String? webhookSecret,
    String? webhookUrl,
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
  }) : this.fromConfig(MullaConfig(
          apiKey: apiKey,
          environment: environment,
          baseUrl: baseUrl,
          webhookSecret: webhookSecret,
          webhookUrl: webhookUrl,
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

  MullaClient.fromConfig(this.config) : _requestor = ApiRequestor(config) {
    if (config.isPublic) {
      throw InvalidArgumentException('MullaClient needs a secret key. For apps, use MullaPublicClient.');
    }
  }

  final MullaConfig config;
  final ApiRequestor _requestor;

  late final ChargeService charges = ChargeService(_requestor);
  late final CheckoutService checkout = CheckoutService(_requestor);
  late final PayoutService payouts = PayoutService(_requestor);
  late final RechargeService recharges = RechargeService(_requestor);
  late final InvoiceService invoices = InvoiceService(_requestor);
  late final CustomerService customers = CustomerService(_requestor);
  late final WebhookEndpointService webhookEndpoint = WebhookEndpointService(_requestor);
  late final ReferenceDataService referenceData = ReferenceDataService(_requestor);

  Environment get environment => config.environment;

  bool get isLive => config.environment == Environment.production;

  String get baseUrl => config.baseUrl;

  /// Webhook verifier using [secret], or the client's `webhookSecret` when omitted.
  Webhook webhooks([String? secret, int toleranceSeconds = 300]) {
    final resolved = secret ?? config.webhookSecret();
    if (resolved == null) {
      throw InvalidArgumentException(
          'No webhook secret. Pass "webhookSecret" to MullaClient(...) or call webhooks(secret).');
    }

    return Webhook(resolved, toleranceSeconds: toleranceSeconds);
  }

  @override
  String toString() =>
      'MullaClient(apiKey: ${config.maskedApiKey()}, environment: ${environment.value}, baseUrl: $baseUrl)';
}

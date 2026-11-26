import 'package:http/http.dart' as http;

import 'enums.dart';
import 'environment.dart';
import 'errors.dart';
import 'http/middleware.dart';
import 'http/retry.dart';
import 'http/transport.dart';
import 'support/uuid.dart';
import 'version.dart';

/// Identifies your integration in the User-Agent, e.g. `AppInfo(name: 'my-shop', version: '1.4.0')`.
class AppInfo {
  const AppInfo({required this.name, this.version, this.url});

  final String name;
  final String? version;
  final String? url;

  static final RegExp _token = RegExp(r'^[A-Za-z0-9._~@+-]{1,64}$');

  /// Builds a header-safe User-Agent token, so app info can never inject headers.
  String format() {
    if (!_token.hasMatch(name)) {
      throw InvalidArgumentException('"appInfo.name" must be 1-64 letters, digits or . _ ~ @ + - (no spaces).');
    }
    final v = version;
    if (v != null && !_token.hasMatch(v)) {
      throw InvalidArgumentException('"appInfo.version" must be 1-64 letters, digits or . _ ~ @ + -.');
    }
    var agent = v != null ? '$name/$v' : name;
    final u = url;
    if (u != null) {
      final parsed = Uri.tryParse(u);
      if (parsed == null || !(parsed.isScheme('https') || parsed.isScheme('http')) || parsed.host.isEmpty) {
        throw InvalidArgumentException('"appInfo.url" must be an http(s) URL.');
      }
      agent += ' (+$parsed)';
    }

    return agent;
  }
}

/// Validated settings shared by [MullaClient] and [MullaPublicClient].
///
/// The SDK never reads environment variables or `.env` files: pass every value explicitly.
/// Null and blank strings count as "not set", so values read from an unset variable fall back to defaults.
class MullaConfig {
  MullaConfig._({
    required String? apiKey,
    required this.environment,
    required this.baseUrl,
    required String? webhookSecret,
    required this.webhookUrl,
    required this.timeout,
    required this.lang,
    required this.deviceId,
    required this.appInfo,
    required this.transport,
    required this.retryStrategy,
    required this.logger,
    required this.middleware,
    required this.sleep,
  })  : _apiKey = apiKey,
        _webhookSecret = webhookSecret;

  /// Settings for a secret-key client. The key prefix decides the environment.
  factory MullaConfig({
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
  }) {
    final key = _blank(apiKey);
    if (key == null) {
      throw InvalidArgumentException(
        'Missing "apiKey". Pass your secret key: MullaClient(apiKey: Platform.environment[\'MULLA_SECRET_KEY\']). '
        'The SDK does not read environment variables itself.',
      );
    }
    final actual = environmentFromApiKey(key);
    if (environment != null && environment != actual) {
      throw InvalidArgumentException(
        '"environment" is ${environment == Environment.production ? 'Environment.production' : 'Environment.test'}, '
        'but "apiKey" is a ${actual == Environment.production ? 'live (sk_live_)' : 'test (sk_test_)'} key. '
        'Use a key from the matching environment.',
      );
    }
    final secret = _blank(webhookSecret);
    final hook = _blank(webhookUrl);
    if (hook != null) {
      _assertWebhookUrl(hook);
    }

    return MullaConfig._build(
      apiKey: key,
      environment: actual,
      baseUrl: baseUrl,
      webhookSecret: secret,
      webhookUrl: hook,
      timeout: timeout,
      maxRetries: maxRetries,
      lang: lang,
      deviceId: deviceId ?? uuidFromSeed('$sdkPlatform:${_keyId(key)}'),
      appInfo: appInfo,
      logger: logger,
      httpClient: httpClient,
      transport: transport,
      middleware: middleware,
      retryStrategy: retryStrategy,
      environmentResolver: environmentResolver,
      sleep: sleep,
    );
  }

  /// Settings for a key-less client that only calls the public, token-based endpoints.
  factory MullaConfig.public({
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
  }) =>
      MullaConfig._build(
        apiKey: null,
        environment: environment,
        baseUrl: baseUrl,
        webhookSecret: null,
        webhookUrl: null,
        timeout: timeout,
        maxRetries: maxRetries,
        lang: lang,
        deviceId: deviceId ?? uuidV4(),
        appInfo: appInfo,
        logger: logger,
        httpClient: httpClient,
        transport: transport,
        middleware: middleware,
        retryStrategy: retryStrategy,
        environmentResolver: environmentResolver,
        sleep: sleep,
      );

  factory MullaConfig._build({
    required String? apiKey,
    required Environment environment,
    required String? baseUrl,
    required String? webhookSecret,
    required String? webhookUrl,
    required Duration timeout,
    required int? maxRetries,
    required Language? lang,
    required String deviceId,
    required AppInfo? appInfo,
    required MullaLogger? logger,
    required http.Client? httpClient,
    required Transport? transport,
    required List<Middleware> middleware,
    required RetryStrategy? retryStrategy,
    required EnvironmentResolver? environmentResolver,
    required Sleep? sleep,
  }) {
    final resolver = environmentResolver ?? const DefaultEnvironmentResolver();
    final url = resolver.resolveBaseUrl(environment, _blank(baseUrl));

    if (!isUuidV4(deviceId)) {
      throw InvalidArgumentException('"deviceId" must be a UUID v4 (use uuidV4() to create one).');
    }
    if (timeout <= Duration.zero) {
      throw InvalidArgumentException('"timeout" must be a positive duration.');
    }
    if (transport != null && httpClient != null) {
      throw InvalidArgumentException(
          'Pass either "httpClient" or "transport", not both: a custom transport does not use it.');
    }
    if (retryStrategy != null && maxRetries != null) {
      throw InvalidArgumentException(
        'Pass either "maxRetries" or "retryStrategy", not both: set the limit on your strategy instead.',
      );
    }
    if (maxRetries != null && maxRetries < 0) {
      throw InvalidArgumentException('"maxRetries" must be 0 or more.');
    }

    return MullaConfig._(
      apiKey: apiKey,
      environment: environment,
      baseUrl: url,
      webhookSecret: webhookSecret,
      webhookUrl: webhookUrl,
      timeout: timeout,
      lang: lang,
      deviceId: deviceId,
      appInfo: appInfo?.format(),
      transport: transport ?? HttpTransport(httpClient),
      retryStrategy: retryStrategy ?? ExponentialBackoff(maxRetries: maxRetries ?? 2),
      logger: logger,
      middleware: List.unmodifiable(middleware),
      sleep: sleep ?? defaultSleep,
    );
  }

  final Environment environment;
  final String baseUrl;
  final String? webhookUrl;
  final Duration timeout;
  final Language? lang;
  final String deviceId;
  final String? appInfo;
  final Transport transport;
  final RetryStrategy retryStrategy;
  final MullaLogger? logger;
  final List<Middleware> middleware;
  final Sleep sleep;
  final String? _apiKey;
  final String? _webhookSecret;

  /// True for a [MullaConfig.public] config (no secret key).
  bool get isPublic => _apiKey == null;

  /// The secret key. Throws for a public config.
  String apiKey() {
    final key = _apiKey;
    if (key == null) {
      throw InvalidArgumentException('This is a public (key-less) client: it has no API key.');
    }

    return key;
  }

  String? webhookSecret() => _webhookSecret;

  String maskedApiKey() {
    final key = _apiKey;

    return key == null ? '(none)' : 'sk_${environment.value}_${_keyId(key)}_****';
  }

  Map<String, Object?> toJson() => {
        'apiKey': maskedApiKey(),
        'environment': environment.value,
        'baseUrl': baseUrl,
        'webhookUrl': webhookUrl,
        'webhookSecret': _webhookSecret == null ? null : '****',
        'timeoutMs': timeout.inMilliseconds,
        'lang': lang?.value,
        'deviceId': deviceId,
        'appInfo': appInfo,
      };

  @override
  String toString() => 'MullaConfig${toJson()}';
}

String _keyId(String apiKey) {
  final parts = apiKey.split('_');

  return parts.length > 2 ? parts[2] : '';
}

String? _blank(String? value) {
  final trimmed = value?.trim();

  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

void _assertWebhookUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) {
    throw InvalidArgumentException('"webhookUrl" "$url" is not a valid URL.');
  }
  if (parsed.userInfo.isNotEmpty || parsed.hasFragment) {
    throw InvalidArgumentException('"webhookUrl" must not contain credentials or a fragment.');
  }
  if (!parsed.isScheme('https') && !(parsed.isScheme('http') && isLocalHost(parsed.host))) {
    throw InvalidArgumentException('"webhookUrl" must use https:// (plain http only for localhost).');
  }
}

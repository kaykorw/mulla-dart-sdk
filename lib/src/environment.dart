import 'errors.dart';

/// Mulla runs sandbox (test) and production (live) as separate servers.
/// The secret key prefix decides which one: `sk_test_...` or `sk_live_...`.
enum Environment {
  test('test'),
  production('live');

  const Environment(this.value);

  /// `test` or `live`, as used in key prefixes.
  final String value;
}

const String apiVersion = 'v1';

/// Official gateway URLs (without the `/v1` suffix).
const Map<Environment, String> officialBaseUrls = {
  Environment.production: 'https://core.mulla.app/gateway',
  Environment.test: 'https://mfs.kayko.dev/gateway',
};

final RegExp _keyPattern = RegExp(r'^sk_(live|test)_[A-Za-z0-9]+_');

/// Reads the environment from a secret key, or throws for a malformed key.
Environment environmentFromApiKey(String apiKey) {
  final match = _keyPattern.firstMatch(apiKey);
  if (match == null) {
    throw InvalidArgumentException(
      'Invalid Mulla secret key. Expected the format "sk_test_<id>_<secret>" or "sk_live_<id>_<secret>".',
    );
  }

  return match[1] == 'live' ? Environment.production : Environment.test;
}

/// Strategy: decides the API base URL for an environment.
abstract interface class EnvironmentResolver {
  String resolveBaseUrl(Environment environment, String? configuredBaseUrl);
}

class DefaultEnvironmentResolver implements EnvironmentResolver {
  const DefaultEnvironmentResolver([this.baseUrls = officialBaseUrls]);

  final Map<Environment, String> baseUrls;

  @override
  String resolveBaseUrl(Environment environment, String? configuredBaseUrl) {
    final url = configuredBaseUrl ?? baseUrls[environment];
    if (url == null) {
      throw InvalidArgumentException(
        'No Mulla API URL is configured for the ${environment.value} environment. Pass "baseUrl".',
      );
    }
    assertSafeUrl(url);

    return withVersion(url);
  }
}

/// HTTPS only, except plain http for local hosts. No credentials, query or fragment.
void assertSafeUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) {
    throw InvalidArgumentException('The Mulla base URL "$url" is not a valid URL.');
  }
  if (parsed.userInfo.isNotEmpty || url.contains('?') || url.contains('#')) {
    throw InvalidArgumentException('The Mulla base URL must not contain credentials, a query string or a fragment.');
  }
  final scheme = parsed.scheme.toLowerCase();
  final host = parsed.host.toLowerCase();
  if (scheme == 'https' || (scheme == 'http' && isLocalHost(host))) {
    return;
  }

  throw InvalidArgumentException(
    'The Mulla base URL must use https:// (got "$scheme://$host"). Plain http is only allowed for localhost.',
  );
}

bool isLocalHost(String host) =>
    const ['localhost', '127.0.0.1', '::1', 'host.docker.internal', '10.0.2.2'].contains(host) ||
    host.endsWith('.localhost') ||
    host.endsWith('.test');

/// Appends `/v1` unless the URL already ends with a version.
String withVersion(String url) {
  final trimmed = url.replaceFirst(RegExp(r'/+$'), '');

  return RegExp(r'/v\d+$').hasMatch(trimmed) ? trimmed : '$trimmed/$apiVersion';
}

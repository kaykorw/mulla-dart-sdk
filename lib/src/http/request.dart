import 'dart:collection';

import '../errors.dart';
import '../support/redactor.dart';

final RegExp _headerName = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$");
final RegExp _badValue = RegExp('[\r\n\x00]');

/// An immutable HTTP request travelling through the middleware pipeline.
/// Header names are stored lower-case; `with*` methods return a changed copy.
class Request {
  Request({
    required String method,
    required this.url,
    Map<String, String> headers = const {},
    this.body,
    this.timeout = const Duration(seconds: 30),
    Map<String, Object?> attributes = const {},
    this.abortTrigger,
  })  : method = method.toUpperCase(),
        headers = UnmodifiableMapView(_checkHeaders(headers)),
        attributes = UnmodifiableMapView(Map.of(attributes));

  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
  final Map<String, Object?> attributes;

  /// Completing this future cancels the request. A cancelled request is never retried.
  final Future<void>? abortTrigger;

  Request withHeader(String name, String value) => _copy(headers: {...headers, name.toLowerCase(): value});

  Request withoutHeader(String name) => _copy(headers: Map.of(headers)..remove(name.toLowerCase()));

  Request withAttribute(String name, Object? value) => _copy(attributes: {...attributes, name: value});

  String? header(String name) => headers[name.toLowerCase()];

  bool hasHeader(String name) => headers.containsKey(name.toLowerCase());

  T attribute<T>(String name, T fallback) {
    final value = attributes[name];

    return value is T ? value : fallback;
  }

  /// Safe to log: the API key and checkout tokens are hidden.
  Map<String, Object?> toJson() => {
        'method': method,
        'url': redactUrl(url),
        'headers': {
          for (final e in headers.entries) e.key: e.key == 'x-api-key' ? '****' : e.value,
        },
        'body': body,
        'timeoutMs': timeout.inMilliseconds,
      };

  @override
  String toString() => 'Request $method ${redactUrl(url)}';

  Request _copy({Map<String, String>? headers, Map<String, Object?>? attributes}) => Request(
        method: method,
        url: url,
        headers: headers ?? this.headers,
        body: body,
        timeout: timeout,
        attributes: attributes ?? this.attributes,
        abortTrigger: abortTrigger,
      );
}

/// Rejects header names/values that could inject extra header lines.
Map<String, String> _checkHeaders(Map<String, String> headers) {
  final out = <String, String>{};
  headers.forEach((name, value) {
    if (!_headerName.hasMatch(name)) {
      throw InvalidArgumentException('Invalid HTTP header name "$name".');
    }
    if (_badValue.hasMatch(value)) {
      throw InvalidArgumentException('Invalid value for HTTP header "$name": it must not contain line breaks.');
    }
    out[name.toLowerCase()] = value;
  });

  return out;
}

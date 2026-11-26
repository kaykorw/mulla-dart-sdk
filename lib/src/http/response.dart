import 'dart:collection';
import 'dart:convert';

/// An HTTP response with a fully read text body.
class Response {
  Response(this.statusCode, {Map<String, String> headers = const {}, this.body = ''})
      : headers = UnmodifiableMapView({for (final e in headers.entries) e.key.toLowerCase(): e.value});

  final int statusCode;
  final Map<String, String> headers;
  final String body;

  bool _decodedOnce = false;
  Object? _decoded;

  String? header(String name) => headers[name.toLowerCase()];

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// The decoded JSON object or list, or null when the body is empty or not JSON.
  Object? json() {
    if (!_decodedOnce) {
      _decodedOnce = true;
      if (body.isNotEmpty) {
        try {
          final Object? data = jsonDecode(body);
          _decoded = data is Map || data is List ? data : null;
        } on FormatException {
          _decoded = null;
        }
      }
    }

    return _decoded;
  }
}

/// A response whose body is still arriving (used for server-sent events).
class StreamedResponse {
  StreamedResponse(this.statusCode, {Map<String, String> headers = const {}, required this.stream})
      : headers = UnmodifiableMapView({for (final e in headers.entries) e.key.toLowerCase(): e.value});

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> stream;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// Reads the whole body into a [Response] (used for error responses).
  Future<Response> toResponse() async => Response(statusCode, headers: headers, body: await utf8.decodeStream(stream));
}

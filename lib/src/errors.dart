import 'http/response.dart';

/// Base class of every exception the SDK throws.
class MullaException implements Exception {
  MullaException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Wrong SDK usage (unknown field, empty id, bad option), raised before any request is sent.
class InvalidArgumentException extends MullaException {
  InvalidArgumentException(super.message, {super.cause});
}

/// A webhook signature is missing, wrong or too old.
class SignatureVerificationException extends MullaException {
  SignatureVerificationException(super.message, {super.cause});
}

/// No HTTP response was received (DNS, refused connection, timeout...).
class ConnectionException extends MullaException {
  ConnectionException(super.message, {this.requestMayHaveBeenSent = true, super.cause});

  /// False only when Mulla certainly never received the request (e.g. DNS failure).
  final bool requestMayHaveBeenSent;
}

/// The request was cancelled through its `abortTrigger`. It is never retried.
class RequestCancelledException extends MullaException {
  RequestCancelledException(super.message, {super.cause});
}

/// The API answered with a non-2xx status.
class ApiException extends MullaException {
  ApiException(
    super.message, {
    required this.statusCode,
    this.errorCode,
    this.body,
    this.headers = const {},
    this.rawBody,
    super.cause,
  });

  final int statusCode;
  final String? errorCode;
  final Map<String, Object?>? body;
  final Map<String, String> headers;
  final String? rawBody;
}

class InvalidRequestException extends ApiException {
  InvalidRequestException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class AuthenticationException extends ApiException {
  AuthenticationException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class PermissionException extends ApiException {
  PermissionException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class NotFoundException extends ApiException {
  NotFoundException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class ConflictException extends ApiException {
  ConflictException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class IdempotencyException extends ConflictException {
  IdempotencyException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

class RateLimitException extends ApiException {
  RateLimitException(super.message,
      {required super.statusCode,
      super.errorCode,
      super.body,
      super.headers,
      super.rawBody,
      super.cause,
      this.retryAfter});

  /// Seconds the server asked to wait, when it said.
  final int? retryAfter;
}

class ApiServerException extends ApiException {
  ApiServerException(super.message,
      {required super.statusCode, super.errorCode, super.body, super.headers, super.rawBody, super.cause});
}

const Map<String, String> _hints = {
  'API_KEY_INVALID': 'Check that you are using a secret key (sk_...) that is active and not expired.',
  'API_KEY_ENVIRONMENT_MISMATCH':
      'Test keys (sk_test_) only work on the sandbox server and live keys (sk_live_) only on production. Check your key and baseUrl.',
  'API_KEY_SCOPE_DENIED': 'This API key is missing the scope required by this endpoint. Add it in the Mulla dashboard.',
  'API_KEY_IP_DENIED': "This server's IP address is not in the key's allowed IP list.",
  'MERCHANT_PENDING_REVIEW': 'Your merchant account is still under review by Mulla.',
  'IDEMPOTENCY_KEY_CONFLICT':
      'This idempotency key was already used. Fetch the existing resource instead of re-sending the request.',
  'VALIDATION_FAILED': 'One or more parameters are invalid. Unknown fields are rejected too.',
};

/// Factory: maps an error response to the matching exception class.
ApiException exceptionFromResponse(Response response) {
  final status = response.statusCode;
  final json = response.json();
  final body = json is Map<String, Object?> ? json : null;
  final code = body?['errorCode'];
  final errorCode = code is String ? code : null;
  final message = _buildMessage(status, errorCode, body);
  final headers = response.headers;
  final raw = response.body;

  if (status == 400) {
    return InvalidRequestException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 401) {
    return AuthenticationException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 403) {
    return PermissionException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 404) {
    return NotFoundException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 409 && (errorCode?.startsWith('IDEMPOTENCY_KEY') ?? false)) {
    return IdempotencyException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 409) {
    return ConflictException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }
  if (status == 429) {
    return RateLimitException(message,
        statusCode: status,
        errorCode: errorCode,
        body: body,
        headers: headers,
        rawBody: raw,
        retryAfter: _retryAfter(response, body));
  }
  if (status >= 500) {
    return ApiServerException(message,
        statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
  }

  return ApiException(message, statusCode: status, errorCode: errorCode, body: body, headers: headers, rawBody: raw);
}

String _buildMessage(int status, String? errorCode, Map<String, Object?>? body) {
  Object? serverMessage = body?['message'];
  if (serverMessage is List) {
    serverMessage = serverMessage.map((m) => '$m').join('; ');
  }
  final text = serverMessage is String && serverMessage.isNotEmpty
      ? serverMessage
      : 'Mulla API request failed with HTTP $status';

  var message = errorCode != null ? '[$errorCode] $text' : text;
  final hint = errorCode != null ? _hints[errorCode] : null;
  if (hint != null) {
    message += ' — $hint';
  }

  return message;
}

int? _retryAfter(Response response, Map<String, Object?>? body) {
  final header = response.header('retry-after');
  final fromHeader = header == null ? null : num.tryParse(header.trim());
  if (fromHeader != null && fromHeader.isFinite) {
    return fromHeader.truncate();
  }
  final fromBody = body?['retryAfter'];
  final parsed = fromBody is num ? fromBody : (fromBody is String ? num.tryParse(fromBody.trim()) : null);

  return parsed != null && parsed.isFinite ? parsed.truncate() : null;
}

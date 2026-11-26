import '../enums.dart';
import '../errors.dart';
import '../support/uuid.dart';

/// Per-request options, passed as the last argument of any service method.
class RequestOptions {
  const RequestOptions({this.idempotencyKey, this.lang, this.timeout, this.headers = const {}, this.abortTrigger});

  final String? idempotencyKey;

  final Language? lang;

  final Duration? timeout;

  final Map<String, String> headers;

  /// Completing this future cancels the request.
  final Future<void>? abortTrigger;

  /// Throws [InvalidArgumentException] for an invalid option.
  void validate() {
    final key = idempotencyKey;
    if (key != null && !isUuid(key)) {
      throw InvalidArgumentException(
        'The "idempotencyKey" must be a UUID (e.g. uuidV4()). Store it with your order so retries reuse it.',
      );
    }
    final t = timeout;
    if (t != null && t <= Duration.zero) {
      throw InvalidArgumentException('The "timeout" request option must be a positive duration.');
    }
  }
}

import '../enums.dart';
import '../errors.dart';
import '../support/uuid.dart';

/// Per-request options, passed as the last argument of any service method.
class RequestOptions {
  const RequestOptions({this.idempotencyKey, this.lang, this.timeout, this.headers = const {}, this.abortTrigger});

  /// Your own UUID. Store it with your order so retries of the same operation reuse it.
  final String? idempotencyKey;

  /// Language of this request's messages.
  final Language? lang;

  /// Time limit for this request.
  final Duration? timeout;

  /// Extra headers for this request.
  final Map<String, String> headers;

  /// Completing this future cancels the request. A cancelled request is never retried.
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

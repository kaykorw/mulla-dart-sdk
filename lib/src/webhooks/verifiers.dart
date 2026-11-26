import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../errors.dart';

/// Strategy: one webhook signature scheme.
abstract interface class SignatureVerifier {
  bool supports(Map<String, String> headers);

  void verify(List<int> payload, Map<String, String> headers, String secret);
}

const _mismatch = 'Webhook signature does not match. Make sure you pass the raw request body '
    '(not re-encoded JSON) and the secret of your current webhook endpoint.';

/// `x-webhook-signature`: hex HMAC-SHA512 of the raw body.
class V1SignatureVerifier implements SignatureVerifier {
  const V1SignatureVerifier();

  static const header = 'x-webhook-signature';

  static String sign(List<int> payload, String secret) => Hmac(sha512, utf8.encode(secret)).convert(payload).toString();

  @override
  bool supports(Map<String, String> headers) => headers.containsKey(header);

  @override
  void verify(List<int> payload, Map<String, String> headers, String secret) {
    final given = (headers[header] ?? '').trim().toLowerCase();
    if (given.isEmpty || !constantTimeEquals(sign(payload, secret), given)) {
      throw SignatureVerificationException(_mismatch);
    }
  }
}

/// `x-webhook-signature-v2` + `x-webhook-timestamp`: HMAC-SHA512 of `"<timestamp>." + body`,
/// rejected outside [toleranceSeconds] to stop replays.
class V2SignatureVerifier implements SignatureVerifier {
  V2SignatureVerifier({this.toleranceSeconds = 300, int Function()? clock})
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  static const signatureHeader = 'x-webhook-signature-v2';
  static const timestampHeader = 'x-webhook-timestamp';

  final int toleranceSeconds;
  final int Function() _clock;

  static String sign(List<int> payload, String secret, int timestamp) =>
      Hmac(sha512, utf8.encode(secret)).convert([...utf8.encode('$timestamp.'), ...payload]).toString();

  @override
  bool supports(Map<String, String> headers) => headers.containsKey(signatureHeader);

  @override
  void verify(List<int> payload, Map<String, String> headers, String secret) {
    final raw = headers[timestampHeader] ?? '';
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      throw SignatureVerificationException('Webhook timestamp header is missing or invalid.');
    }
    final timestamp = int.parse(raw);
    if (toleranceSeconds > 0 && (_clock() - timestamp).abs() > toleranceSeconds) {
      throw SignatureVerificationException(
        'Webhook timestamp is outside the $toleranceSeconds second tolerance '
        '(possible replay, or the server clock is wrong).',
      );
    }
    final given = (headers[signatureHeader] ?? '').trim().toLowerCase();
    if (given.isEmpty || !constantTimeEquals(sign(payload, secret, timestamp), given)) {
      throw SignatureVerificationException(_mismatch);
    }
  }
}

/// Compares two strings without leaking where they differ.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }

  return diff == 0;
}

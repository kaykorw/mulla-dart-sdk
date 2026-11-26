import 'package:mulla_dart/mulla_dart.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  Future<Object> errorFor(int status, Map<String, Object?> body) async {
    final (mulla, fake) = makeClient(maxRetries: 0);
    fake.pushJson(body, status: status);
    try {
      await mulla.charges.retrieve('chg_1');
    } on Object catch (e) {
      return e;
    }
    fail('expected an exception');
  }

  test('status codes map to exception classes', () async {
    expect(await errorFor(400, {}), isA<InvalidRequestException>());
    expect(await errorFor(401, {}), isA<AuthenticationException>());
    expect(await errorFor(403, {}), isA<PermissionException>());
    expect(await errorFor(404, {}), isA<NotFoundException>());
    expect(await errorFor(409, {'errorCode': 'IDEMPOTENCY_KEY_CONFLICT'}), isA<IdempotencyException>());
    expect(await errorFor(409, {}), isA<ConflictException>());
    expect(
        await errorFor(429, {'retryAfter': 3}), isA<RateLimitException>().having((e) => e.retryAfter, 'retryAfter', 3));
    expect(await errorFor(502, {}), isA<ApiServerException>());
    expect(await errorFor(418, {}), isA<ApiException>());
  });

  test('messages carry the error code, server message and a hint', () async {
    final e = await errorFor(400, {
      'errorCode': 'VALIDATION_FAILED',
      'message': ['phone_number is invalid', 'amount too low'],
    }) as ApiException;
    expect(e.message, startsWith('[VALIDATION_FAILED] phone_number is invalid; amount too low — '));
    expect(e.statusCode, 400);
    expect(e.errorCode, 'VALIDATION_FAILED');
    expect(e.rawBody, contains('amount too low'));
  });

  test('a missing scope is named', () async {
    final e = await errorFor(403, {'errorCode': 'API_KEY_SCOPE_DENIED', 'message': 'Forbidden'}) as PermissionException;
    expect(e.message, endsWith('Required scope: CHARGES.'));
  });

  test('a non-JSON error body still gives a useful message', () async {
    final (mulla, fake) = makeClient(maxRetries: 0);
    fake.push(Response(502, body: '<html>Bad gateway</html>'));
    await expectLater(
      mulla.charges.retrieve('chg_1'),
      throwsA(isA<ApiServerException>().having((e) => e.message, 'message', 'Mulla API request failed with HTTP 502')),
    );
  });
}

// Run: MULLA_WEBHOOK_SECRET=... dart run example/webhook_server.dart
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  final process = WebhookProcessor(
    secret: Platform.environment['MULLA_WEBHOOK_SECRET'] ?? '',
    dispatcher: EventDispatcher()
      ..on(WebhookEventType.chargeSuccess, (event) => print('Paid: ${event.objectId()}'))
      ..on(WebhookEventType.chargeFailed, (event) => print('Failed: ${event.objectId()}'))
      ..onAny((event) => print('Event ${event.type} ${event.id}')),
  );

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
  print('Listening on http://localhost:8080/mulla/webhook');

  await for (final request in server) {
    if (request.method != 'POST' || request.uri.path != '/mulla/webhook') {
      request.response.statusCode = 404;
      await request.response.close();
      continue;
    }
    final body = await request.expand((chunk) => chunk).toList(); // raw bytes: the signature covers the exact body
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name] = values.first);

    final result = await process(body, headers);
    request.response
      ..statusCode = result.status
      ..headers.contentType = ContentType.json
      ..write(result.jsonBody);
    await request.response.close();
  }
}

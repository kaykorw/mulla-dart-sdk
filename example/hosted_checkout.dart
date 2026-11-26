// Your backend creates the session. A browser opens checkoutUrl, or a Flutter app
// receives id + token and pays with mulla_flutter.
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  final session = await mulla.charges.createCheckout(const CreateCheckoutParams(
    amount: 2500,
    reason: 'Order #1001',
    metadata: {'orderId': 1001},
    successUrl: 'https://shop.example/orders/1001/thanks',
    cancelUrl: 'https://shop.example/cart',
  ));

  print('Browser: ${session.checkoutUrl}');
  print('App:     sessionId=${session.id} token=${session.token}');
}

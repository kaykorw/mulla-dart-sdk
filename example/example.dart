// Run: MULLA_SECRET_KEY=sk_test_... dart run example/example.dart
//
// More examples in this folder: hosted_checkout.dart, payout.dart and webhook_server.dart.
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  final charge = await mulla.charges.initiate(const InitiateChargeParams(
    provider: Provider.mtnRw,
    amount: 5000, // RWF
    phoneNumber: '0788000000',
    reason: 'Order #1001',
  ));
  print('Charge ${charge.id} is ${charge.status?.value}. Approve the prompt on the phone...');

  final result = await mulla.charges.waitForFinalStatus(charge.id);
  print(result.isSuccessful ? 'Paid.' : 'Not paid: ${result.status?.value}');
}

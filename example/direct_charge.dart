// Run: MULLA_SECRET_KEY=sk_test_... dart run example/direct_charge.dart
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  final charge = await mulla.charges.initiate(const InitiateChargeParams(
    provider: Provider.mtnRw,
    amount: 100,
    phoneNumber: '0788000000',
    reason: 'SDK example',
  ));
  print('Charge ${charge.id} is ${charge.status?.value}. Approve the prompt on the phone...');

  final result = await mulla.charges.waitForFinalStatus(charge.id);
  print('Final status: ${result.status?.value}');
}

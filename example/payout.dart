import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  try {
    final payout = await mulla.payouts.initiate(const CreatePayoutParams(
      provider: Provider.mtnRw,
      amount: 1000,
      phoneNumber: '0788000000',
      reason: 'Refund for order #1001',
    ));
    print('Payout ${payout.id}: ${payout.status?.value}');
  } on InvalidRequestException catch (e) {
    if (e.errorCode == 'INSUFFICIENT_BALANCE') {
      print('Top up your Mulla balance first.');
    } else {
      rethrow;
    }
  }
}

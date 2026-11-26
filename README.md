# Mulla Dart SDK

<!-- x-release-please-start-version -->

> This guide applies to `mulla_dart` **0.1.1** and the Mulla API **v1**.

<!-- x-release-please-end -->

The official Dart library for [Mulla](https://mulla.app), the mobile money payment gateway for Rwanda. Use it to take payments from MTN Mobile Money and Airtel Money, send money to phones, and bill customers with invoices, from any Dart program.

## What you can do

- **Collect payments.** Send a payment request to a customer's phone, or open a payment page hosted by Mulla.
- **Get paid in your app.** Let a Flutter or web app take a payment without holding any secret.
- **Know when a payment finishes.** Receive Mulla's notifications (webhooks) on your server, or check the status yourself.
- **Send money.** Pay out to a mobile money number, and top up your Mulla balance to fund those payouts.
- **Bill customers.** Keep a customer list, send invoices and track their payments.
- **Look up reference data.** Banks, bank branches, countries, currencies and key permissions.
- **Test without real money.** Use Mulla's sandbox, or the built-in fakes that never touch the network.

## Which client do you need?

The package has two entry points. Pick the one that matches where your code runs.

| Client              | Needs                         | Runs in                                                         | Can do                                                 |
| ------------------- | ----------------------------- | --------------------------------------------------------------- | ------------------------------------------------------ |
| `MullaClient`       | Your secret key (`sk_test_…`) | Your server: shelf, dart_frog, Serverpod, scripts, command line | Everything in the Mulla API                            |
| `MullaPublicClient` | Nothing                       | Flutter apps and Dart web pages                                 | Pay one payment page or invoice, and follow its status |

Building a Flutter app? Use [`mulla_flutter`](https://pub.dev/packages/mulla_flutter). It's built on `MullaPublicClient` and adds ready-made payment screens.

> **Never put your secret key in an app or a web page.** Anyone can extract it from the download and use it to move your money. Keep it on your server; apps use `MullaPublicClient`, which needs no key.

## Contents

- [Before you start](#before-you-start)
- [Install](#install)
- [Your first payment](#your-first-payment)
- [How Mulla payments work](#how-mulla-payments-work)
- [Guides](#guides)
  - [Collect a payment from a phone](#collect-a-payment-from-a-phone)
  - [Use a payment page or your app](#use-a-payment-page-or-your-app)
  - [Get notified when a payment finishes](#get-notified-when-a-payment-finishes)
  - [Send money to a phone](#send-money-to-a-phone)
  - [Top up your Mulla balance](#top-up-your-mulla-balance)
  - [Manage customers](#manage-customers)
  - [Send invoices](#send-invoices)
  - [Look up banks, countries and currencies](#look-up-banks-countries-and-currencies)
  - [Find past records](#find-past-records)
  - [Handle errors](#handle-errors)
  - [Prevent duplicate payments](#prevent-duplicate-payments)
  - [Log requests](#log-requests)
  - [Set time limits and cancel requests](#set-time-limits-and-cancel-requests)
  - [Change how the client connects](#change-how-the-client-connects)
  - [Test your integration](#test-your-integration)
  - [Go live](#go-live)
- [Reference](#reference)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Releasing](#releasing)
- [License](#license)

## Before you start

You need:

- **Dart 3.5 or newer.** Flutter 3.24 or newer includes it.
- **A Mulla merchant account.**
- **A secret API key** from the Mulla dashboard. Test keys start with `sk_test_` and live keys with `sk_live_`.
- **The right permissions on the key.** Mulla calls them *scopes*, and each part of the API needs one:

| To use                                 | The key needs |
| -------------------------------------- | ------------- |
| Charges and payment pages              | `CHARGES`     |
| Payouts                                | `PAYOUTS`     |
| Balance top-ups (recharges)            | `RECHARGES`   |
| Invoices                               | `INVOICES`    |
| Customers                              | `CUSTOMERS`   |
| Webhook setup (register, rotate, test) | `WEBHOOKS`    |

If a key lacks a scope, the error message names the one to add.

## Install

```bash
dart pub add mulla_dart
```

Then import it:

```dart
import 'package:mulla_dart/mulla_dart.dart';
```

## Your first payment

This example uses a test key, so it runs in Mulla's sandbox and no real money moves.

```dart
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  // The SDK never reads environment variables itself: pass the key in.
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  final charge = await mulla.charges.initiate(const InitiateChargeParams(
    provider: Provider.mtnRw,
    amount: 5000, // RWF
    phoneNumber: '0788000000',
    reason: 'Order #1001',
  ));
  print('Charge ${charge.id} is ${charge.status}');

  final result = await mulla.charges.waitForFinalStatus(charge.id);
  if (result.isSuccessful) {
    print('Paid!');
  }
}
```

Run it with `MULLA_SECRET_KEY=sk_test_... dart run`. Waiting like this is fine for a script. On a real server, let Mulla notify you instead: see [Get notified when a payment finishes](#get-notified-when-a-payment-finishes).

## How Mulla payments work

### Payments finish later

Mobile money payments aren't instant. Mulla sends a request to the customer's phone, and the customer approves it with their PIN. Every payment therefore starts as `PENDING` and ends in one of three states:

```text
PENDING ──► SUCCESSFUL   the customer approved
        ├─► FAILED       declined, wrong PIN, not enough money…
        └─► EXPIRED      the customer didn't answer in time
```

Your code learns the final state in one of two ways:

- **Webhooks (recommended).** Mulla calls a URL on your server when the payment finishes.
- **Checking.** You ask Mulla for the status, with `retrieve` or `waitForFinalStatus`.

### Two ways to collect money

| Method                                           | Who collects the phone number | Best for                              |
| ------------------------------------------------ | ----------------------------- | ------------------------------------- |
| [Direct charge](#collect-a-payment-from-a-phone) | You                           | Your own checkout form, point of sale |
| [Payment page](#use-a-payment-page-or-your-app)  | Mulla's page, or your app     | Websites, mobile apps, payment links  |

### Test and live mode

Your key decides where requests go, so you never configure a server address:

| Key starts with | Mode                   | Server                           |
| --------------- | ---------------------- | -------------------------------- |
| `sk_test_`      | Sandbox, no real money | `https://mfs.kayko.dev/gateway`  |
| `sk_live_`      | Production, real money | `https://core.mulla.app/gateway` |

Test and live data are completely separate: a test payment never shows up in live mode.

### Amounts and phone numbers

- **Amounts** are whole Rwandan francs (RWF), not cents. `5000` means RWF 5,000. The minimum is 10.
- **Phone numbers** can be typed the way customers write them. `0788 000 000`, `250788000000`, `788000000` and `+250 0788 000 000` all become `+250788000000`.
- **The network** follows from the number: 078 and 079 are MTN, 072 and 073 are Airtel. `providerForPhoneNumber()` works it out, and `isRwandanMobileNumber()` checks a form field before you send anything.

### Words used in this guide

| Word            | Meaning                                                                                       |
| --------------- | --------------------------------------------------------------------------------------------- |
| Charge          | A request for money from a customer's phone.                                                  |
| Payment page    | A Mulla-hosted page (a *checkout session*) where the customer picks their network and pays.   |
| Payout          | Money you send from your Mulla balance to a phone.                                            |
| Recharge        | Money you add to your Mulla balance from a phone, to fund payouts.                            |
| Webhook         | A message Mulla sends to your server when something happens, such as a finished payment.      |
| Webhook secret  | A password Mulla uses to sign each webhook, so you can check it really came from Mulla.       |
| Scope           | A permission on your API key, such as `CHARGES`.                                              |
| Idempotency key | A unique label on a request. If the same request arrives twice, Mulla processes it only once. |
| Metadata        | Your own data, such as an order number, stored with a payment and sent back in webhooks.      |

## Guides

### Collect a payment from a phone

Use this when you collect the network and phone number yourself. Needs the `CHARGES` scope.

```dart
final charge = await mulla.charges.initiate(const InitiateChargeParams(
  provider: Provider.airtelRw,
  amount: 12000,
  phoneNumber: '0730000000',
  reason: 'Order #1001',
  metadata: {'orderId': 1001},
));

await orders.update(1001, mullaChargeId: charge.id);
```

The customer gets a prompt on their phone. You'll learn the outcome from the `charge.success`, `charge.failed` or `charge.expired` webhook. To check yourself, call `mulla.charges.retrieve(charge.id)`.

### Use a payment page or your app

Use this when you'd rather not build a payment form. Your server creates a *payment page* (checkout session), and the customer pays on Mulla's page or inside your app. Needs the `CHARGES` scope.

**1. Your server creates the payment page:**

```dart
final session = await mulla.charges.createCheckout(const CreateCheckoutParams(
  amount: 25000,
  reason: 'Order #1001',
  metadata: {'orderId': 1001},
  successUrl: 'https://shop.example/orders/1001/thanks',
  cancelUrl: 'https://shop.example/cart',
));
```

**2a. On a website,** send the customer to `session.checkoutUrl`.

**2b. In an app,** send `session.id` and `session.token` to the app. The token only allows paying and viewing that one payment page, so it's safe in an app. The app pays with [`mulla_flutter`](https://pub.dev/packages/mulla_flutter)'s screens, or with `MullaPublicClient` directly:

```dart
final mulla = MullaPublicClient(environment: Environment.test);

await mulla.checkout.pay(sessionId, token, const PayParams(provider: Provider.mtnRw, phoneNumber: '0788000000'));

await for (final update in mulla.checkout.watch(sessionId, token)) {
  print(update.status);
}
```

`watch()` keeps a live connection open to Mulla. If that isn't possible (web browsers, or a network that drops quiet connections), it checks every 3 seconds instead. You don't need to handle this yourself.

**3. Confirm on your server** with the webhook or `mulla.charges.retrieve(...)` before you deliver the order. An app, or a visit to your success URL, can be faked; Mulla's answer can't.

### Get notified when a payment finishes

Webhooks are messages Mulla sends to your server when something happens: a payment succeeds or fails, a payout completes, an invoice is paid.

**1. Register your URL once.** Needs the `WEBHOOKS` scope. Mulla returns a webhook secret and shows it only this once, so store it safely, for example in your server's environment as `MULLA_WEBHOOK_SECRET`:

```dart
final endpoint = await mulla.webhookEndpoint.create(
    const CreateWebhookEndpointParams(url: 'https://shop.example/mulla/webhook'));
print(endpoint.secret);

final check = await mulla.webhookEndpoint.test();
print(check.ok ? 'Your server received it' : 'Mulla got HTTP ${check.statusCode}');
```

Each key has one webhook URL, and test and live keys each have their own.

**2. Handle the requests.** `WebhookProcessor` checks that each request really comes from Mulla, skips ones you've already handled, runs your code, and tells you what to reply:

```dart
final process = WebhookProcessor(
  secret: Platform.environment['MULLA_WEBHOOK_SECRET']!,
  dispatcher: EventDispatcher()
    ..on(WebhookEventType.chargeSuccess, (event) => orders.markPaidByChargeId(event.objectId()!))
    ..on(WebhookEventType.chargeFailed, (event) => orders.markFailedByChargeId(event.objectId()!)),
  isDuplicate: (event) => webhookEvents.exists(event.id),
);

// With shelf:
Future<Response> webhook(Request request) async {
  final body = await request.read().expand((chunk) => chunk).toList();
  final result = await process(body, request.headers);
  return Response(result.status, body: result.jsonBody, headers: {'content-type': 'application/json'});
}
```

| Your server replies | When                                                   | What Mulla does next        |
| ------------------- | ------------------------------------------------------ | --------------------------- |
| `200`               | Your code finished, or you'd already handled it        | Nothing                     |
| `400`               | The signature is missing, wrong or more than 5 min old | Nothing                     |
| `500`               | Your code threw an error                               | Sends the event again later |

Two rules keep the signature check working:

- **Pass the request body exactly as received** (the raw bytes or string). If you decode and re-encode the JSON, the signature no longer matches.
- **Keep your server clock correct.** Webhooks signed more than 5 minutes ago are rejected, which stops someone replaying an old message.

Using another framework? Call `Webhook.constructEvent(rawBody, headers, secret)`: it returns the `Event` or throws `SignatureVerificationException`. A complete `dart:io` server is in [example/webhook_server.dart](example/webhook_server.dart).

**3. Manage the webhook later:**

```dart
await mulla.webhookEndpoint.retrieve();
await mulla.webhookEndpoint.update(const UpdateWebhookEndpointParams(url: 'https://shop.example/new-webhook'));
await mulla.webhookEndpoint.update(const UpdateWebhookEndpointParams(isActive: false)); // pause webhooks

final rotated = await mulla.webhookEndpoint.rotateSecret();
print(rotated.secret); // store the new one; the old one stops working
```

### Send money to a phone

A payout sends money from your Mulla balance to a mobile money number, for example a refund or a supplier payment. Needs the `PAYOUTS` scope.

```dart
final payout = await mulla.payouts.initiate(const CreatePayoutParams(
  provider: Provider.mtnRw,
  amount: 15000,
  phoneNumber: '0788000000',
  reason: 'Refund for order #1001', // required
));
```

A payout is done when its status is `COMPLETED` (`payout.isSuccessful`). You'll also get the `payout.success` or `payout.failed` webhook. If your balance is too low, you get an `InvalidRequestException` whose `errorCode` is `INSUFFICIENT_BALANCE`.

### Top up your Mulla balance

A recharge moves money from a mobile money number into your Mulla balance, so you can fund payouts. Needs the `RECHARGES` scope.

```dart
final recharge = await mulla.recharges.initiate(const InitiateRechargeParams(
  provider: Provider.mtnRw,
  amount: 50000,
  phoneNumber: '0788000000', // this phone approves and pays
  reason: 'Payout float',
));

final done = await mulla.recharges.waitForFinalStatus(recharge.id);
print(done.isSuccessful ? 'Balance topped up' : 'Top-up ${done.status}');
```

Mulla adds your account's top-up fee, so the phone pays the amount plus the fee. The amount must be at least your account's minimum top-up.

### Manage customers

Keep a list of the people you bill. Needs the `CUSTOMERS` scope.

```dart
final customer = await mulla.customers.create(const CustomerParams(
  fullName: 'Jane Doe',
  email: 'jane@example.com',
  phone: '0788000000',
  city: 'Kigali',
));

await mulla.customers.update(customer.id, const CustomerParams(fullName: 'Jane Uwase'));
final found = await mulla.customers.list(const CustomerListFilters(keyword: 'Jane'));

await mulla.customers.blacklist(customer.id); // they stay in your list but can't be invoiced
await mulla.customers.whitelist(customer.id);
```

### Send invoices

An invoice is a bill the customer can pay later, from their phone or through a link. Needs the `INVOICES` scope.

**Create an invoice:**

```dart
final invoice = await mulla.invoices.create(CreateInvoiceParams(
  customer: customer.id,
  items: const [
    InvoiceItemParams(name: 'Website design', unitPrice: 150000),
    InvoiceItemParams(name: 'Hosting (months)', unitPrice: 10000, quantity: 12),
  ],
  dueDate: DateTime(2026, 12, 31),
  notes: 'Thank you for your business',
));
```

**Ask the customer to pay** with a prompt on their phone:

```dart
await mulla.invoices.pay(invoice.id, const PayInvoiceParams(provider: Provider.mtnRw, phoneNumber: '0788000000'));
```

If an attempt fails, the invoice stays open and the customer can try again. When it's paid, you get the `invoice.paid` webhook.

**Change or follow up an invoice:**

```dart
await mulla.invoices.update(invoice.id, UpdateInvoiceParams(dueDate: DateTime(2027, 1, 15)));
await mulla.invoices.updateStatus(invoice.id, InvoiceStatus.cancelled);

final attempts = await mulla.invoices.listPayments(invoice.id);
```

Apps can show and pay an invoice without a key, using `MullaPublicClient`: `invoices.retrievePublic`, `invoices.pay` and `invoices.watch`.

### Look up banks, countries and currencies

Lists that help you build forms. They need no particular scope.

```dart
final banks = await mulla.referenceData.banks(const BankFilters(country: 'RW'));
for (final bank in banks.data) {
  print(bank.get('name'));
}

await mulla.referenceData.bankBranches(const BankBranchFilters(swift: 'BKIGRWRW'));
await mulla.referenceData.countries(const CountryFilters(isSupported: true));
await mulla.referenceData.currencies();
await mulla.referenceData.scopes();
```

These records aren't typed classes: read any field with `get('field')`, or all of them with `raw`.

### Find past records

Every `list` method returns **one page** of results. Call `.autoPaging()` to go through **every result**; the SDK fetches the next pages as you go.

```dart
// One page
final page = await mulla.charges.list(const ChargeListFilters(limit: 20));
print('${page.data.length} of ${page.total}');
if (page.hasMore) {
  final next = await page.nextPage();
}

// Every successful charge since 1 November
await for (final charge in mulla.charges.list(ChargeListFilters(
  status: ChargeStatus.successful,
  startDate: DateTime(2026, 11, 1),
)).autoPaging()) {
  print('${charge.reference} ${charge.amount}');
}
```

Each service has its own filters: `ChargeListFilters`, `PayoutListFilters`, `RechargeListFilters`, `InvoiceListFilters` and `CustomerListFilters`. They support search keywords, status, dates and sorting.

### Handle errors

Every error the SDK throws is a `MullaException`, with a message that says what went wrong and, where possible, how to fix it. Catch the specific types you can act on:

```dart
try {
  await mulla.payouts.initiate(params);
} on InvalidRequestException catch (e) {
  if (e.errorCode == 'INSUFFICIENT_BALANCE') {
    // Ask an admin to top up the balance.
  }
} on PermissionException catch (e) {
  print(e.message);
} on ConnectionException catch (e) {
  // No answer from Mulla. See "Prevent duplicate payments" before trying again.
} on MullaException catch (e) {
  print(e.message);
}
```

Errors from Mulla's API also carry `statusCode` (the HTTP status), `errorCode` (Mulla's code, such as `INSUFFICIENT_BALANCE`), and the response in `body` and `rawBody`. Every error type is listed under [Errors](#errors).

### Prevent duplicate payments

The SDK already protects you:

- It retries a request that changes something (creating a charge or payout) **only** when Mulla can't have processed it. It never repeats a payment that might have gone through.
- Every such request carries an idempotency key, so Mulla ignores an accidental second copy.

For the strongest protection, create the key yourself, store it with your order, and reuse it every time you retry that order:

```dart
order.mullaKey ??= uuidV4(); // save the order after this
try {
  await mulla.charges.initiate(params, RequestOptions(idempotencyKey: order.mullaKey));
} on ConnectionException catch (e) {
  if (e.requestMayHaveBeenSent) {
    // The outcome is unknown. Wait for the webhook, or look the charge up, before trying again.
  }
} on IdempotencyException {
  // A charge with this key already exists. Don't create another.
}
```

### Log requests

Pass a `logger` to see each request the SDK makes, how long it took, and its result. Your key, tokens and request bodies are never passed to it.

```dart
final mulla = MullaClient(
  apiKey: key,
  logger: (level, message, context) => print('[${level.name}] $message $context'),
);
```

To identify your software in Mulla's logs, add `appInfo: AppInfo(name: 'my-shop', version: '1.4.0')`.

### Set time limits and cancel requests

Each request has a 30-second time limit. Change it for the whole client, or for a single request:

```dart
final mulla = MullaClient(apiKey: key, timeout: const Duration(seconds: 15));

final cancel = Completer<void>();
final charge = mulla.charges.retrieve(id, RequestOptions(
  timeout: const Duration(seconds: 5),
  abortTrigger: cancel.future, // complete it to cancel the request
));
```

A cancelled request throws `RequestCancelledException` and is never retried.

### Change how the client connects

Most apps never need these options. They're there for special setups:

| You want to…                                    | Use                                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Use a local or staging Mulla server             | `baseUrl: 'http://localhost:3000/gateway'` (the SDK adds `/v1`)                           |
| Reach a local server from the Android emulator  | `baseUrl: 'http://10.0.2.2:3000/gateway'`                                                 |
| Go through a proxy, or use a native HTTP client | `httpClient:` any `package:http` client, such as `cronet_http` or `cupertino_http`        |
| Add a header to every request                   | `middleware: [Middleware.fn((request, next) => next(request.withHeader('x-trace', id)))]` |
| Get answers in another language                 | `lang: Language.fr` (also `en`, `rw`, `sw`)                                               |
| Retry more or less                              | `maxRetries: 0` turns retries off; the default is 2                                       |

Plain `http://` works only for local addresses. Every other server must use HTTPS, so your key is never sent unencrypted.

### Test your integration

`package:mulla_dart/testing.dart` lets your tests run without calling Mulla. `FakeTransport` stands in for the network and answers with responses you queue:

```dart
import 'package:mulla_dart/testing.dart';

final fake = FakeTransport()..pushJson({'id': 'chg_1', 'status': 'PENDING', 'amount': 5000});
final mulla = MullaClient(apiKey: 'sk_test_abc_xyz', transport: fake);

await checkout(mulla); // your code

fake.assertSent((r) => r.url.endsWith('/charges/initiate'));
print(fake.lastBody);
```

To test other paths, queue:

- `pushError(400, 'INSUFFICIENT_BALANCE')` for an API error;
- `pushConnectionError()` for a network failure;
- `pushEvents([...])` for live status updates.

`WebhookSigner.event('charge.success', {...}, secret)` builds a correctly signed webhook request for your webhook tests. `MullaFixtures.checkoutSession()` and `MullaFixtures.invoice()` give ready-made responses.

To try the real sandbox, use a `sk_test_` key and Mulla's test phone numbers.

### Go live

Before switching to real money:

- [ ] Your live key (`sk_live_…`) is stored on the server only, never in an app or in source control.
- [ ] The live key has only the scopes you use.
- [ ] You registered a webhook with the **live** key and stored its secret. Test and live secrets differ.
- [ ] Your webhook handler checks for duplicates and replies within a few seconds.
- [ ] Orders are marked paid only after the webhook or `retrieve` confirms it, never on the app's word or a visit to your success URL.
- [ ] Payment requests use a stored idempotency key (see [Prevent duplicate payments](#prevent-duplicate-payments)).
- [ ] Your server clock is synchronised, so webhook signatures aren't rejected.

## Reference

### Services and methods

| Service                 | Methods                                                                                                                                  | Scope       |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `mulla.charges`         | `initiate`, `createCheckout`, `retrieve`, `list`, `waitForFinalStatus`                                                                   | `CHARGES`   |
| `mulla.checkout`        | `retrieve`, `pay`, `watch`, `eventsUrl` (use the payment page's token)                                                                   | None        |
| `mulla.payouts`         | `initiate`, `retrieve`, `list`, `waitForFinalStatus`                                                                                     | `PAYOUTS`   |
| `mulla.recharges`       | `initiate`, `retrieve`, `list`, `waitForFinalStatus`                                                                                     | `RECHARGES` |
| `mulla.invoices`        | `create`, `retrieve`, `list`, `update`, `updateStatus`, `listPayments`, `retrievePayment`, `retrievePublic`, `pay`, `watch`, `eventsUrl` | `INVOICES`  |
| `mulla.customers`       | `create`, `retrieve`, `list`, `update`, `blacklist`, `whitelist`                                                                         | `CUSTOMERS` |
| `mulla.webhookEndpoint` | `create`, `retrieve`, `update`, `rotateSecret`, `test`                                                                                   | `WEBHOOKS`  |
| `mulla.referenceData`   | `banks`, `bankBranches`, `countries`, `currencies`, `scopes`                                                                             | None        |
| `mulla.webhooks()`      | Returns a `Webhook` checker using the client's `webhookSecret`                                                                           | None        |

`MullaPublicClient` has `checkout` (`retrieve`, `pay`, `watch`, `eventsUrl`) and `invoices` (`retrievePublic`, `pay`, `watch`, `eventsUrl`).

Helpers: `normalizePhoneNumber`, `providerForPhoneNumber`, `isRwandanMobileNumber`, `uuidV4`.

### Client options

All options are named parameters of `MullaClient(...)` and `MullaPublicClient(...)`. They're checked when the client is created, so a mistake shows up at startup, not on the first payment. Empty strings count as "not set", so a missing environment variable falls back to the default.

| Option                | Default             | What it does                                                                      |
| --------------------- | ------------------- | --------------------------------------------------------------------------------- |
| `apiKey`              | Required            | Your secret key, `sk_test_…` or `sk_live_…` (`MullaClient` only).                 |
| `environment`         | Taken from the key  | `Environment.test` or `Environment.production`. Required for `MullaPublicClient`. |
| `baseUrl`             | Mulla's servers     | Another server. HTTPS only, except local addresses.                               |
| `webhookSecret`       | None                | Default secret for `mulla.webhooks()`.                                            |
| `webhookUrl`          | None                | Default URL for `webhookEndpoint.create()`.                                       |
| `timeout`             | 30 seconds          | Time limit for each request.                                                      |
| `maxRetries`          | `2`                 | Extra attempts for requests that are safe to repeat. `0` turns retries off.       |
| `lang`                | Mulla's default     | Language of Mulla's messages: `Language.en`, `fr`, `rw` or `sw`.                  |
| `appInfo`             | None                | Your software's name and version, added to every request.                         |
| `logger`              | None                | Receives a line per request. Never receives keys, tokens or bodies.               |
| `deviceId`            | Worked out for you  | A UUID v4 identifying this installation.                                          |
| `httpClient`          | `http.Client()`     | Your own `package:http` client.                                                   |
| `middleware`          | None                | Code that runs on every request, for example to add headers.                      |
| `transport`           | Real network        | Replaces the network layer. Tests use `FakeTransport`.                            |
| `retryStrategy`       | Exponential backoff | Advanced: your own retry rules. Can't be combined with `maxRetries`.              |
| `environmentResolver` | Mulla's servers     | Advanced: your own choice of server per mode.                                     |
| `sleep`               | `Future.delayed`    | Advanced: how the SDK waits between retries. Tests pass `(_) async {}`.           |

### Request options

Every method takes an optional `RequestOptions` as its last argument:

| Option           | What it does                                             |
| ---------------- | -------------------------------------------------------- |
| `idempotencyKey` | Your own duplicate-protection key for this request.      |
| `timeout`        | Time limit for this request only.                        |
| `lang`           | Language of Mulla's messages for this request only.      |
| `headers`        | Extra HTTP headers.                                      |
| `abortTrigger`   | A `Future`; when it completes, the request is cancelled. |

### Statuses

| Object           | Still in progress                  | Final                                                     | Succeeded when |
| ---------------- | ---------------------------------- | --------------------------------------------------------- | -------------- |
| Charge, recharge | `pending`                          | `successful`, `failed`, `expired`                         | `successful`   |
| Payout           | `pending`, `approved`, `scheduled` | `completed`, `failed`, `rejected`, `cancelled`, `expired` | `completed`    |
| Invoice          | `issued`, `pending`, `overdue`     | `paid`, `cancelled`                                       | `paid`         |
| Invoice payment  | `pending`, `processing`            | `successful`, `failed`, `cancelled`, `expired`            | `successful`   |

Each object has `isFinal` and `isSuccessful` (`isPaid` for invoices). If Mulla adds a status this version doesn't know, `status` is `null` instead of crashing your code; the original value is still in `raw`.

### Webhook events

| Event            | `WebhookEventType` | Sent when                           |
| ---------------- | ------------------ | ----------------------------------- |
| `charge.success` | `chargeSuccess`    | A charge or payment page was paid   |
| `charge.failed`  | `chargeFailed`     | A charge failed                     |
| `charge.expired` | `chargeExpired`    | The customer didn't answer in time  |
| `payout.success` | `payoutSuccess`    | A payout completed                  |
| `payout.failed`  | `payoutFailed`     | A payout failed                     |
| `invoice.paid`   | `invoicePaid`      | An invoice was paid in full         |
| `webhook.test`   | `webhookTest`      | You called `webhookEndpoint.test()` |

An `Event` has `id`, `type` and `data`, plus `objectId()`, `amount()` and `metadata()` helpers. Use `dispatcher.onType('name', ...)` for event types newer than this SDK.

### Errors

| Exception                        | HTTP status | Common causes                                                            |
| -------------------------------- | ----------- | ------------------------------------------------------------------------ |
| `InvalidRequestException`        | 400         | A wrong parameter, an amount below the minimum, not enough balance       |
| `AuthenticationException`        | 401         | The key is wrong, expired or revoked                                     |
| `PermissionException`            | 403         | A missing scope, a blocked IP address, a test key on live or the reverse |
| `NotFoundException`              | 404         | Nothing with that id, or a wrong payment page token                      |
| `ConflictException`              | 409         | A payment for this is already in progress                                |
| `IdempotencyException`           | 409         | This idempotency key was already used                                    |
| `RateLimitException`             | 429         | Too many requests; `retryAfter` says how long to wait                    |
| `ApiServerException`             | 500–599     | A problem on Mulla's side                                                |
| `ConnectionException`            | None        | No answer from Mulla; check `requestMayHaveBeenSent`                     |
| `RequestCancelledException`      | None        | You cancelled the request with `abortTrigger`                            |
| `SignatureVerificationException` | None        | A webhook's signature is missing, wrong or too old                       |
| `InvalidArgumentException`       | None        | The SDK was called incorrectly; nothing was sent                         |

### Retry rules

| Request                                                     | Retried after                                                                   |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Reading (`retrieve`, `list`)                                | Network errors, and HTTP 408, 429, 500, 502, 503 and 504                        |
| Changing something (`initiate`, `create`, `pay`, `update`…) | HTTP 429 and 503 (refused before processing), or a connection that never opened |

Waits grow from 0.5 to 8 seconds, with a little randomness, and follow Mulla's `Retry-After` header. A payment request that times out or gets a 500 error is **not** retried, because Mulla may already have sent the prompt or the money.

## Examples

The [example](example) folder has complete programs. Run each with `MULLA_SECRET_KEY=sk_test_... dart run example/<file>`.

| File                                                 | Shows                                                |
| ---------------------------------------------------- | ---------------------------------------------------- |
| [example.dart](example/example.dart)                 | Charging a phone and waiting for the result          |
| [hosted_checkout.dart](example/hosted_checkout.dart) | Creating a payment page for a website or an app      |
| [payout.dart](example/payout.dart)                   | Sending money and handling a low balance             |
| [webhook_server.dart](example/webhook_server.dart)   | A `dart:io` server that receives and checks webhooks |

## Troubleshooting

| Problem                                                   | Likely cause and fix                                                                                      |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| "Missing apiKey" at startup                               | The environment variable isn't set where the program runs. The SDK doesn't read it for you.               |
| "Invalid Mulla secret key"                                | You passed a public key (`pk_…`) or a partial key. Use the full secret key, `sk_test_…` or `sk_live_…`.   |
| `PermissionException` with `API_KEY_SCOPE_DENIED`         | The key lacks the scope named in the message. Create a key with that scope.                               |
| `PermissionException` with `API_KEY_IP_DENIED`            | The key only accepts certain IP addresses. Add your server's address, or remove the restriction.          |
| `PermissionException` with `API_KEY_ENVIRONMENT_MISMATCH` | A test key is calling the live server, or the reverse. Remove `baseUrl` and let the key decide.           |
| Webhook signature doesn't match                           | You passed re-encoded JSON instead of the raw body, or used the wrong secret (test and live differ).      |
| Webhooks rejected as "outside the tolerance"              | Your server clock is wrong. Turn on automatic time synchronisation.                                       |
| `NotFoundException` from `checkout.retrieve` in an app    | A wrong id or token, or a test payment page opened with `Environment.production`.                         |
| The customer gets no prompt                               | The number is on the other network, or the phone is off or has no signal. Check `providerForPhoneNumber`. |
| `watch()` updates arrive every few seconds                | Expected on the web, or when the network drops quiet connections. The SDK checks every 3 seconds instead. |
| "Could not reach Mulla"                                   | A network problem. For payment requests, read `requestMayHaveBeenSent` before trying again.               |

## Contributing

```bash
dart pub get
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test test/unit
MULLA_SECRET_KEY=sk_test_... dart test test/integration   # against the sandbox
```

Keep the SDK consistent with the other Mulla SDKs (PHP, Node, Laravel and others): the same services, method names, errors, retry rules and webhook checks. The shared webhook test in `test/fixtures` must keep passing. Write commit messages as [Conventional Commits](https://www.conventionalcommits.org), because the changelog is built from them.

## Releasing

Releases are automated with [release-please](https://github.com/googleapis/release-please):

1. Every push to `main` updates a release pull request. It bumps the version in `pubspec.yaml`, `lib/src/version.dart` and this README, and adds the new entries to `CHANGELOG.md`.
2. Merging that pull request creates the `vX.Y.Z` tag and the GitHub release.
3. The tag runs `.github/workflows/publish.yml`, which tests the package and publishes it to pub.dev.

How the next version is chosen: release-please reads the commit messages on `main` since the last release.

| Commit message starts with                      | Next version (while below 1.0) | Shows in the changelog |
| ----------------------------------------------- | ------------------------------ | ---------------------- |
| `fix:`                                          | 0.1.0 → 0.1.1                  | Yes, under Bug Fixes   |
| `feat:`                                         | 0.1.0 → 0.2.0                  | Yes, under Features    |
| `feat!:` or a `BREAKING CHANGE:` footer         | 0.1.0 → 0.2.0                  | Yes, flagged breaking  |
| `docs:`, `test:`, `ci:`, `chore:`, `refactor:`  | No release on its own          | No                     |

Pull requests are squash-merged, so the pull request title becomes the commit message. The `PR title` check rejects titles that don't follow this format.

One-time setup:

1. Publish the first version by hand with `dart pub publish`. pub.dev can only enable automated publishing for a package that already exists. Then tag that commit so release-please knows where to start: `git tag v0.1.0 && git push origin v0.1.0`.
2. On pub.dev, open the package's **Admin** tab and enable **Automated publishing** from GitHub Actions for `kaykorw/mulla-dart-sdk`, with the tag pattern `v{{version}}`.
3. In the GitHub repository, add a `RELEASE_PLEASE_TOKEN` secret: a personal access token with write access to contents and pull requests. Tags created with the default `GITHUB_TOKEN` don't start other workflows, so without it nothing is published.

Publish `mulla_dart` before `mulla_flutter`, which depends on its released version.

## License

MIT. See [LICENSE](LICENSE).

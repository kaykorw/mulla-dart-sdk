# Mulla Dart SDK

<!-- x-release-please-start-version -->

> This guide applies to `mulla_dart` **0.1.0** and the Mulla API **v1**.

<!-- x-release-please-end -->

The official Dart library for Mulla, the mobile money payment gateway for Rwanda.

It has two clients:

| Client              | Key                         | Use it in                                       | What it can do                                                         |
| ------------------- | --------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------- |
| `MullaClient`       | Secret key (`sk_test_...`)  | Dart servers: shelf, dart_frog, Serverpod, CLIs | The whole API: charges, checkout, payouts, invoices, webhooks...       |
| `MullaPublicClient` | None                        | Flutter apps, Dart web                          | Pay a checkout session or an invoice, and watch its status live        |

Building a Flutter app? Use [`mulla_flutter`](https://pub.dev/packages/mulla_flutter). It is built on `MullaPublicClient` and adds ready-made checkout widgets.

Why use it instead of calling the API yourself:

- **Typed.** Params, models and statuses are Dart classes and enums, so your editor autocompletes everything.
- **Safe by default.** It adds the required headers, retries only when a payment can't be duplicated, and never logs your key.
- **Small.** It depends only on `http` and `crypto`, both published by the Dart team.
- **Same shape as the other Mulla SDKs** (PHP, Node, Laravel...): same services, method names, errors and retry rules.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [How Mulla payments work](#how-mulla-payments-work)
- [Guides](#guides): [Charge a phone number](#charge-a-phone-number) · [Hosted checkout and apps](#hosted-checkout-and-apps) · [Handle webhooks](#handle-webhooks) · [Payouts](#send-a-payout) · [Invoices](#invoice-a-customer) · [Lists](#list-and-filter-records) · [Errors](#handle-errors) · [Avoid duplicate payments](#avoid-duplicate-payments) · [Testing](#test-your-integration)
- [Reference](#reference)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Requirements

- **Dart 3.5 or newer.**
- **A Mulla merchant account** and a secret API key from the Mulla dashboard.
- **The right scopes on the key** for each service: `CHARGES`, `PAYOUTS`, `INVOICES`, `RECHARGES` or `CUSTOMERS`.

> **`MullaClient` is server-side only.** Your secret key can move money. Never put it in a Flutter app or a web page, where anyone can extract it. Apps use `MullaPublicClient`, which needs no key.

## Installation

```bash
dart pub add mulla_dart
```

## Quick start

This uses the sandbox, so no real money moves.

```dart
import 'dart:io';

import 'package:mulla_dart/mulla_dart.dart';

Future<void> main() async {
  // The SDK never reads environment variables itself: pass the key explicitly.
  final mulla = MullaClient(apiKey: Platform.environment['MULLA_SECRET_KEY']);

  final charge = await mulla.charges.initiate(const InitiateChargeParams(
    provider: Provider.mtnRw,
    amount: 5000, // RWF
    phoneNumber: '0788000000',
    reason: 'Order #1001',
  ));
  print('${charge.id} ${charge.status}'); // PENDING until the customer answers

  final result = await mulla.charges.waitForFinalStatus(charge.id);
  if (result.isSuccessful) {
    // Mark the order as paid.
  }
}
```

In production, use [webhooks](#handle-webhooks) instead of waiting.

## How Mulla payments work

**Payments finish later.** The customer approves a mobile money payment on their phone, so every charge starts as `PENDING`:

```text
PENDING ──► SUCCESSFUL   the customer approved
        ├─► FAILED       declined, wrong PIN, not enough money…
        └─► EXPIRED      the customer did not answer in time
```

**Two ways to collect:** a [direct charge](#charge-a-phone-number) (you collect the network and number), or a [checkout session](#hosted-checkout-and-apps) (Mulla's web page, or your Flutter app with `mulla_flutter`).

**Two ways to learn the result:** [webhooks](#handle-webhooks) (recommended), or polling with `waitForFinalStatus`.

**Test and live mode.** The key prefix decides the server; you don't configure a URL.

| Key prefix | Mode                   | Server                           |
| ---------- | ---------------------- | -------------------------------- |
| `sk_test_` | Sandbox, no real money | `https://mfs.kayko.dev/gateway`  |
| `sk_live_` | Production, real money | `https://core.mulla.app/gateway` |

To use another server, such as a local one, pass `baseUrl`. The SDK adds `/v1`.

**Amounts** are whole RWF, not cents (minimum 10). **Phone numbers** are converted for you: `0788 000 000`, `250788000000`, `788000000` and the common slip `+250 0788 000 000` all become `+250788000000`. `normalizePhoneNumber()` and `providerForPhoneNumber()` are exported for form input.

## Guides

### Charge a phone number

```dart
final charge = await mulla.charges.initiate(const InitiateChargeParams(
  provider: Provider.airtelRw,
  amount: 12000,
  phoneNumber: '0730000000',
  reason: 'Order #1001', // shown to the customer
  metadata: {'orderId': 1001}, // your own data, kept with the charge
));
await orders.update(1001, mullaChargeId: charge.id);
```

Then wait for the `charge.success` or `charge.failed` webhook, or check with `mulla.charges.retrieve(charge.id)`.

### Hosted checkout and apps

**1. Your server creates a session:**

```dart
final session = await mulla.charges.createCheckout(const CreateCheckoutParams(
  amount: 25000,
  reason: 'Order #1001',
  successUrl: 'https://shop.example/orders/1001/thanks',
  cancelUrl: 'https://shop.example/cart',
));
```

**2a. On the web,** redirect to `session.checkoutUrl`.

**2b. In an app,** send `session.id` and `session.token` to the app. The token only lets the holder read and pay that one session. The app then pays with `mulla_flutter`'s widgets, or with `MullaPublicClient` directly:

```dart
final mulla = MullaPublicClient(environment: Environment.test);

await mulla.checkout.pay(sessionId, token, const PayParams(provider: Provider.mtnRw, phoneNumber: '0788000000'));

await for (final update in mulla.checkout.watch(sessionId, token)) {
  print(update.status); // PENDING ... then SUCCESSFUL / FAILED / EXPIRED, then the stream closes
}
```

`watch()` uses server-sent events. On the web, where streamed responses are buffered, or if the stream drops, it falls back to polling every 3 seconds. Invoices work the same way: `invoices.retrievePublic`, `invoices.pay` and `invoices.watch`.

**3. Confirm on your server** with the webhook or `mulla.charges.retrieve(...)`. Never mark an order paid only because the app or the return URL says so.

### Handle webhooks

**1. Register your URL once** and store the secret it returns. Mulla shows it only once:

```dart
final endpoint = await mulla.webhookEndpoint.create(
    const CreateWebhookEndpointParams(url: 'https://shop.example/mulla/webhook'));
// Save endpoint.secret as MULLA_WEBHOOK_SECRET.
await mulla.webhookEndpoint.test(); // sends a "webhook.test" event
```

**2. Handle requests** with `WebhookProcessor`. It verifies the signature, skips duplicates, runs your listeners and tells you what to reply:

```dart
final process = WebhookProcessor(
  secret: Platform.environment['MULLA_WEBHOOK_SECRET']!,
  dispatcher: EventDispatcher()
    ..on(WebhookEventType.chargeSuccess, (event) => orders.markPaidByChargeId(event.objectId()!))
    ..on(WebhookEventType.chargeFailed, (event) => orders.markFailedByChargeId(event.objectId()!)),
  isDuplicate: (event) => webhookEvents.exists(event.id),
);

// shelf
Future<Response> webhook(Request request) async {
  final body = await request.read().expand((chunk) => chunk).toList(); // the raw bytes
  final result = await process(body, request.headers);
  return Response(result.status, body: result.jsonBody, headers: {'content-type': 'application/json'});
}
```

| Reply | When                                         | What Mulla does next |
| ----- | -------------------------------------------- | -------------------- |
| `200` | Your listeners finished, or it's a duplicate | Nothing              |
| `400` | The signature is missing, wrong or too old   | Nothing              |
| `500` | One of your listeners threw                  | Retries later        |

To verify by hand, call `Webhook.constructEvent(rawBody, headers, secret)`. It throws `SignatureVerificationException` if the check fails. A complete `dart:io` server is in [example/webhook_server.dart](example/webhook_server.dart).

Mulla signs the **raw body**, so pass the exact bytes you received, never re-encoded JSON. Signed webhooks older than 5 minutes are rejected (replay protection), so keep your server clock correct.

### Send a payout

```dart
final payout = await mulla.payouts.initiate(const CreatePayoutParams(
  provider: Provider.mtnRw,
  amount: 15000,
  phoneNumber: '0788000000',
  reason: 'Refund for order #1001', // required
));
```

A payout has succeeded when its status is `COMPLETED` (`payout.isSuccessful`). Low balance → `InvalidRequestException` with `errorCode == 'INSUFFICIENT_BALANCE'`.

### Invoice a customer

```dart
final customer = await mulla.customers.create(const CustomerParams(fullName: 'Jane Doe', phone: '0788000000'));

final invoice = await mulla.invoices.create(CreateInvoiceParams(
  customer: customer.id,
  items: const [
    InvoiceItemParams(name: 'Website design', unitPrice: 150000),
    InvoiceItemParams(name: 'Hosting (months)', unitPrice: 10000, quantity: 12),
  ],
  dueDate: DateTime(2026, 12, 31),
));

await mulla.invoices.pay(invoice.id, const PayInvoiceParams(provider: Provider.mtnRw, phoneNumber: '0788000000'));
```

### List and filter records

`await list()` returns **one page**. `.autoPaging()` streams **every item**, fetching pages as needed:

```dart
final page = await mulla.charges.list(const ChargeListFilters(limit: 20));
page.data; page.total; page.hasMore; await page.nextPage();

await for (final charge in mulla.charges.list(ChargeListFilters(
  status: ChargeStatus.successful,
  startDate: DateTime(2026, 11, 1),
)).autoPaging()) {
  print('${charge.reference} ${charge.amount}');
}
```

### Handle errors

Every exception extends `MullaException`:

```dart
try {
  await mulla.payouts.initiate(params);
} on InvalidRequestException catch (e) {
  if (e.errorCode == 'INSUFFICIENT_BALANCE') { /* ask an admin to top up */ }
} on PermissionException catch (e) {
  print(e.message); // names the missing scope, or the IP / environment problem
} on MullaException catch (e) {
  print(e.message); // includes the error code and, often, a hint on how to fix it
}
```

API exceptions carry `statusCode`, `errorCode`, `body` and `rawBody`.

### Avoid duplicate payments

Writes are retried only when Mulla clearly didn't process them, and every POST carries an idempotency key. For the strongest protection, create the key once, store it with your order and reuse it:

```dart
order.mullaKey ??= uuidV4();
try {
  await mulla.charges.initiate(params, RequestOptions(idempotencyKey: order.mullaKey));
} on ConnectionException catch (e) {
  if (e.requestMayHaveBeenSent) { /* unknown outcome: wait for the webhook or look it up */ }
} on IdempotencyException {
  // A charge with this key already exists. Don't create another.
}
```

### Test your integration

`package:mulla_dart/testing.dart` lets your tests run without calling Mulla:

```dart
import 'package:mulla_dart/testing.dart';

final fake = FakeTransport()..pushJson({'id': 'chg_1', 'status': 'PENDING', 'amount': 5000});
final mulla = MullaClient(apiKey: 'sk_test_abc_xyz', transport: fake);

await checkout(mulla); // your code

fake.assertSent((r) => r.url.endsWith('/charges/initiate'));
fake.lastBody; // the JSON your code sent
```

Queue `pushError(400, 'INSUFFICIENT_BALANCE')`, `pushConnectionError()` or `pushEvents([...])` (server-sent events) to test other paths. `WebhookSigner.event('charge.success', {...}, secret)` builds a correctly signed webhook request, and `MullaFixtures` has ready-made payloads.

## Reference

### Services and methods

| Service                 | Methods                                                                                                                         | Scope       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `mulla.charges`         | `initiate`, `createCheckout`, `retrieve`, `list`, `waitForFinalStatus`                                                          | `CHARGES`   |
| `mulla.checkout`        | `retrieve`, `pay`, `watch`, `eventsUrl` (public; uses the session token)                                                        | —           |
| `mulla.payouts`         | `initiate`, `retrieve`, `list`, `waitForFinalStatus`                                                                            | `PAYOUTS`   |
| `mulla.recharges`       | `initiate`, `retrieve`, `list`, `waitForFinalStatus`                                                                            | `RECHARGES` |
| `mulla.invoices`        | `create`, `retrieve`, `list`, `update`, `updateStatus`, `listPayments`, `retrievePayment`, `retrievePublic`, `pay`, `watch`, `eventsUrl` | `INVOICES`  |
| `mulla.customers`       | `create`, `retrieve`, `list`, `update`, `blacklist`, `whitelist`                                                                | `CUSTOMERS` |
| `mulla.webhookEndpoint` | `create`, `retrieve`, `update`, `rotateSecret`, `test`                                                                          | —           |
| `mulla.referenceData`   | `banks`, `bankBranches`, `countries`, `currencies`, `scopes`                                                                    | —           |

`MullaPublicClient` has `checkout` and `invoices` (`retrievePublic`, `pay`, `watch`, `eventsUrl`).

### Client options

All options are named constructor parameters. Each one is checked when the client is created, so a mistake fails at startup, not on the first payment. Null and blank strings mean "not set".

| Option                | Default              | Description                                                                                |
| --------------------- | -------------------- | ------------------------------------------------------------------------------------------ |
| `apiKey`              | — (required)         | `sk_test_...` or `sk_live_...` (`MullaClient` only).                                       |
| `environment`         | From the key         | Guard for `MullaClient`; **required** for `MullaPublicClient`.                             |
| `baseUrl`             | Official server      | HTTPS only, except local hosts (`localhost`, `10.0.2.2` for the Android emulator...).      |
| `webhookSecret`       | —                    | Default secret for `mulla.webhooks()`.                                                     |
| `webhookUrl`          | —                    | Default URL for `webhookEndpoint.create()`.                                                |
| `timeout`             | 30 s                 | Time limit per request.                                                                    |
| `maxRetries`          | `2`                  | Extra attempts for requests that are safe to retry. `0` turns retries off.                 |
| `lang`                | API default          | `Language.en`, `fr`, `rw` or `sw`.                                                         |
| `deviceId`            | Derived from the key | UUID v4 sent as `x-device-id` (random per instance for the public client).                 |
| `appInfo`             | —                    | `AppInfo(name: 'my-shop', version: '1.4.0')`, added to the User-Agent.                     |
| `logger`              | —                    | `(level, message, context) {}`. Keys, tokens and bodies are never passed; a throwing logger is ignored. |
| `httpClient`          | `http.Client()`      | Your own `package:http` client (proxy, `cronet_http`, `cupertino_http`...).                |
| `middleware`          | `[]`                 | `Middleware.fn((request, next) => next(request.withHeader(...)))`.                         |
| `transport`           | `HttpTransport`      | Replaces the HTTP layer (see `FakeTransport`).                                             |
| `retryStrategy`       | `ExponentialBackoff` | Advanced. Can't be combined with `maxRetries`.                                             |
| `environmentResolver` | Official servers     | Advanced.                                                                                  |
| `sleep`               | `Future.delayed`     | Advanced: how retries wait. Tests pass `(_) async {}`.                                     |

**Per request:** pass `RequestOptions(idempotencyKey:, lang:, timeout:, headers:, abortTrigger:)` as the last argument. A request cancelled through `abortTrigger` throws `RequestCancelledException` and is never retried.

### Statuses

| Object           | In progress                        | Final                                                     | `isSuccessful` |
| ---------------- | ---------------------------------- | --------------------------------------------------------- | -------------- |
| Charge, recharge | `pending`                          | `successful`, `failed`, `expired`                         | `successful`   |
| Payout           | `pending`, `approved`, `scheduled` | `completed`, `failed`, `rejected`, `cancelled`, `expired` | `completed`    |
| Invoice          | `issued`, `pending`, `overdue`     | `paid`, `cancelled`                                       | (`isPaid`)     |
| Invoice payment  | `pending`, `processing`            | `successful`, `failed`, `cancelled`, `expired`            | `successful`   |

An unknown status from a newer API becomes `null` instead of throwing; the original value stays in `model.raw`.

### Errors

| Exception                        | HTTP    | Common causes                                                           |
| -------------------------------- | ------- | ----------------------------------------------------------------------- |
| `InvalidRequestException`        | 400     | Invalid parameters, amount below the minimum, insufficient balance      |
| `AuthenticationException`        | 401     | The key is invalid, expired or revoked                                  |
| `PermissionException`            | 403     | Missing scope, IP not allowed, test/live mismatch, account not approved |
| `NotFoundException`              | 404     | No object with that id (or a wrong checkout token)                      |
| `ConflictException`              | 409     | A payment for this is already in progress                               |
| `IdempotencyException`           | 409     | The idempotency key was already used                                    |
| `RateLimitException`             | 429     | Too many requests; `retryAfter` says how long to wait                   |
| `ApiServerException`             | 500–599 | A problem on Mulla's side                                               |
| `ConnectionException`            | —       | No response; check `requestMayHaveBeenSent`                             |
| `RequestCancelledException`      | —       | You cancelled the request through `abortTrigger`                        |
| `SignatureVerificationException` | —       | A webhook signature is missing, wrong or too old                        |
| `InvalidArgumentException`       | —       | Wrong SDK usage, raised before any request                              |

### Retry rules

| Request                                         | Retried after                                                       |
| ----------------------------------------------- | ------------------------------------------------------------------- |
| Reads (`retrieve`, `list`)                      | Network errors and 408, 429, 500, 502, 503, 504                     |
| Writes (`initiate`, `create`, `pay`, `update`…) | 429 and 503 (rejected before processing), or a connection that never opened |

Backoff goes from 0.5 s to 8 s, with jitter, and follows `Retry-After`. A write that times out or gets a 500 is **not** retried, because Mulla may already have sent the prompt or the money.

## Troubleshooting

| Problem                                               | Likely cause and fix                                                                                         |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Webhook signature doesn't match                       | You passed re-encoded JSON instead of the raw bytes, or used the wrong secret (test and live differ).        |
| `PermissionException` with `API_KEY_SCOPE_DENIED`     | Add the scope named in the message to your key in the dashboard.                                             |
| `PermissionException` with `API_KEY_ENVIRONMENT_MISMATCH` | A test key is calling production, or the reverse. Remove `baseUrl` and let the key decide.               |
| `InvalidArgumentException` about the base URL         | `baseUrl` must use HTTPS, except for local hosts.                                                            |
| `NotFoundException` from `checkout.retrieve` in an app | Wrong session id or token, or a test session opened against the live environment.                           |
| `watch()` updates arrive every few seconds on web     | Expected: browsers buffer streamed responses, so the SDK polls instead.                                      |
| `watch()` switches to polling after a while           | Expected when the event stream drops or stays silent for 45 s (a proxy cutting idle connections). Updates keep coming. |

## Contributing

```bash
dart pub get
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test test/unit
MULLA_SECRET_KEY=sk_test_... dart test test/integration   # against the sandbox
```

Rules: same behaviour as the other Mulla SDKs (services, method names, errors, retry rules, webhook checks); the shared webhook vector in `test/fixtures` must keep passing; [Conventional Commits](https://www.conventionalcommits.org) for messages, since release-please builds the changelog from them.

## Releasing

Releases are automated: merging the release PR that release-please opens tags `vX.Y.Z`, and the tag runs `.github/workflows/publish.yml`, which tests and publishes to pub.dev.

One-time setup:

1. Publish the first version by hand, since pub.dev can only enable automated publishing for an existing package: `dart pub publish`.
2. On pub.dev, open the package's **Admin** tab, enable **Automated publishing** from GitHub Actions for `kaykorw/mulla-dart-sdk`, with the tag pattern `v{{version}}`.
3. In the GitHub repository, add a `RELEASE_PLEASE_TOKEN` secret (a personal access token with `contents` and `pull-requests` write access). Tags pushed with the default `GITHUB_TOKEN` don't start other workflows, so without it nothing gets published.

Publish `mulla_dart` before `mulla_flutter`, which depends on its released version.

## License

MIT. See [LICENSE](LICENSE).

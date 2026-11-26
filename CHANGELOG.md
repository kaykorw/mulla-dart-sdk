# Changelog

## 0.1.1

- Adds `example/example.dart`, the example pub.dev shows on the package page.
- Documents every service and method, and rewrites the README in plain language with a guide for each part of the API.
- Removes redundant code comments. No API or behaviour changes.

## 0.1.0

- First release: full Mulla API v1 (charges, checkout, payouts, recharges, invoices, customers, webhook endpoint, reference data), webhook verification, `MullaPublicClient` for apps, and testing helpers.
- Phone numbers typed with a 0 after the country code (`+250 0788…`) are normalised to `+250788…`.
- `watch()` switches to polling when the event stream goes silent for 45 s, and polls never overlap.
- A stream that times out while connecting now closes its connection.

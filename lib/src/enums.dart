/// Implemented by every SDK enum: [value] is the exact string the API uses.
abstract interface class ApiEnum {
  String get value;
}

T? _parse<T extends ApiEnum>(List<T> values, Object? raw) {
  if (raw is! String) {
    return null;
  }
  for (final v in values) {
    if (v.value == raw) {
      return v;
    }
  }

  return null;
}

enum Provider implements ApiEnum {
  mtnRw('MTN_RW', 'MTN Mobile Money'),
  airtelRw('AIRTEL_RW', 'Airtel Money');

  const Provider(this.value, this.label);

  @override
  final String value;

  /// Human-readable name, e.g. "MTN Mobile Money".
  final String label;

  /// The matching provider, or null for an unknown value (new API values never throw).
  static Provider? tryParse(Object? raw) => _parse(values, raw);
}

enum Language implements ApiEnum {
  en('en'),
  fr('fr'),
  rw('rw'),
  sw('sw');

  const Language(this.value);

  @override
  final String value;

  static Language? tryParse(Object? raw) => _parse(values, raw);
}

enum Currency implements ApiEnum {
  rwf('RWF'),
  usd('USD'),
  ugx('UGX'),
  kes('KES'),
  tzs('TZS'),
  bif('BIF');

  const Currency(this.value);

  @override
  final String value;

  static Currency? tryParse(Object? raw) => _parse(values, raw);
}

/// Status of a charge (and of a recharge, which uses the same values).
enum ChargeStatus implements ApiEnum {
  pending('PENDING'),
  successful('SUCCESSFUL'),
  failed('FAILED'),
  expired('EXPIRED');

  const ChargeStatus(this.value);

  @override
  final String value;

  bool get isFinal => this != pending;

  static ChargeStatus? tryParse(Object? raw) => _parse(values, raw);
}

typedef RechargeStatus = ChargeStatus;

enum PayoutStatus implements ApiEnum {
  pending('PENDING'),
  approved('APPROVED'),
  rejected('REJECTED'),
  completed('COMPLETED'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  scheduled('SCHEDULED'),
  expired('EXPIRED');

  const PayoutStatus(this.value);

  @override
  final String value;

  bool get isFinal => const [completed, failed, rejected, cancelled, expired].contains(this);

  static PayoutStatus? tryParse(Object? raw) => _parse(values, raw);
}

enum InvoiceStatus implements ApiEnum {
  issued('ISSUED'),
  pending('PENDING'),
  paid('PAID'),
  overdue('OVERDUE'),
  cancelled('CANCELLED');

  const InvoiceStatus(this.value);

  @override
  final String value;

  bool get isFinal => this == paid || this == cancelled;

  static InvoiceStatus? tryParse(Object? raw) => _parse(values, raw);
}

/// Status of one payment attempt on an invoice.
enum PaymentStatus implements ApiEnum {
  pending('PENDING'),
  processing('PROCESSING'),
  successful('SUCCESSFUL'),
  failed('FAILED'),
  cancelled('CANCELLED'),
  expired('EXPIRED');

  const PaymentStatus(this.value);

  @override
  final String value;

  bool get isFinal => this != pending && this != processing;

  static PaymentStatus? tryParse(Object? raw) => _parse(values, raw);
}

enum WebhookEventType implements ApiEnum {
  chargeSuccess('charge.success'),
  chargeFailed('charge.failed'),
  chargeExpired('charge.expired'),
  payoutSuccess('payout.success'),
  payoutFailed('payout.failed'),
  invoicePaid('invoice.paid'),
  webhookTest('webhook.test');

  const WebhookEventType(this.value);

  @override
  final String value;

  static WebhookEventType? tryParse(Object? raw) => _parse(values, raw);
}

/// A permission on an API key.
enum ApiScope implements ApiEnum {
  charges('CHARGES'),
  payouts('PAYOUTS'),
  invoices('INVOICES'),
  recharges('RECHARGES'),
  customers('CUSTOMERS');

  const ApiScope(this.value);

  @override
  final String value;

  static ApiScope? tryParse(Object? raw) => _parse(values, raw);
}

enum SortDirection implements ApiEnum {
  asc('ASC'),
  desc('DESC');

  const SortDirection(this.value);

  @override
  final String value;
}

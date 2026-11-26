import 'enums.dart';
import 'errors.dart';

typedef Metadata = Map<String, Object?>;

final RegExp _separators = RegExp(r'[\s().-]');

/// Converts Rwandan numbers to international format: `0788 000 000`, `250788000000`,
/// `788000000` and the common slip `+250 0788 000 000` all become `+250788000000`.
/// Other numbers are returned trimmed, without separators after a leading `+`.
String normalizePhoneNumber(String value) {
  final trimmed = value.trim();
  final plus = trimmed.startsWith('+');
  final digits = (plus ? trimmed.substring(1) : trimmed).replaceAll(_separators, '');
  // Rwandan mobile numbers are +250 7XXXXXXXX; a 0 typed after the country code is a local-format slip.
  final rwanda = RegExp(r'^(?:250)?0?(7\d{8})$').firstMatch(digits);
  if (rwanda != null && (!plus || digits.startsWith('250'))) return '+250${rwanda[1]}';

  return plus ? '+$digits' : trimmed;
}

/// True for a Rwandan MTN or Airtel mobile number in any accepted spelling.
bool isRwandanMobileNumber(String value) => RegExp(r'^\+2507[2389]\d{7}$').hasMatch(normalizePhoneNumber(value));

/// Guesses the network from a Rwandan number (078/079 MTN, 072/073 Airtel).
Provider? providerForPhoneNumber(String value) {
  final n = normalizePhoneNumber(value);
  if (RegExp(r'^\+2507[89]\d{7}$').hasMatch(n)) return Provider.mtnRw;
  if (RegExp(r'^\+2507[23]\d{7}$').hasMatch(n)) return Provider.airtelRw;

  return null;
}

String _phone(String value, String field) {
  if (value.trim().isEmpty) {
    throw InvalidArgumentException('"$field" cannot be empty.');
  }

  return normalizePhoneNumber(value);
}

void _amount(num amount) {
  if (!amount.isFinite || amount <= 0) {
    throw InvalidArgumentException('"amount" must be a positive number of RWF (minimum 10).');
  }
}

/// Builder-style params: every class turns into the API's snake_case body with [toApi].
abstract class Params {
  const Params();

  Map<String, Object?> toApi();
}

class InitiateChargeParams extends Params {
  const InitiateChargeParams({
    required this.provider,
    required this.amount,
    required this.phoneNumber,
    this.currency,
    this.reason,
    this.application,
    this.notes,
    this.billingDetails,
    this.shippingDetails,
    this.metadata,
    this.customer,
  });

  final Provider provider;

  /// Amount in RWF (whole francs, not cents). Minimum 10.
  final num amount;
  final String phoneNumber;
  final Currency? currency;
  final String? reason;
  final String? application;
  final String? notes;
  final Map<String, Object?>? billingDetails;
  final Map<String, Object?>? shippingDetails;
  final Metadata? metadata;

  /// Customer id.
  final String? customer;

  @override
  Map<String, Object?> toApi() {
    _amount(amount);

    return {
      'provider': provider,
      'amount': amount,
      'phone_number': _phone(phoneNumber, 'phoneNumber'),
      'currency': currency,
      'reason': reason,
      'application': application,
      'notes': notes,
      'billing_details': billingDetails,
      'shipping_details': shippingDetails,
      'metadata': metadata,
      'customer': customer == null ? null : {'id': customer},
    };
  }
}

class CreateCheckoutParams extends Params {
  const CreateCheckoutParams({
    required this.amount,
    required this.successUrl,
    required this.cancelUrl,
    this.currency,
    this.reason,
    this.application,
    this.notes,
    this.billingDetails,
    this.shippingDetails,
    this.metadata,
    this.customer,
  });

  final num amount;
  final String successUrl;
  final String cancelUrl;
  final Currency? currency;
  final String? reason;
  final String? application;
  final String? notes;
  final Map<String, Object?>? billingDetails;
  final Map<String, Object?>? shippingDetails;
  final Metadata? metadata;
  final String? customer;

  @override
  Map<String, Object?> toApi() {
    _amount(amount);
    if (successUrl.trim().isEmpty || cancelUrl.trim().isEmpty) {
      throw InvalidArgumentException('"successUrl" and "cancelUrl" are required.');
    }

    return {
      'amount': amount,
      'success_url': successUrl,
      'cancel_url': cancelUrl,
      'currency': currency,
      'reason': reason,
      'application': application,
      'notes': notes,
      'billing_details': billingDetails,
      'shipping_details': shippingDetails,
      'metadata': metadata,
      'customer': customer == null ? null : {'id': customer},
    };
  }
}

class CreatePayoutParams extends Params {
  const CreatePayoutParams({
    required this.provider,
    required this.amount,
    required this.phoneNumber,
    required this.reason,
    this.metadata,
  });

  final Provider provider;
  final num amount;
  final String phoneNumber;
  final String reason;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() {
    _amount(amount);
    if (reason.trim().isEmpty) {
      throw InvalidArgumentException('"reason" is required for a payout.');
    }

    return {
      'provider': provider,
      'amount': amount,
      'phone_number': _phone(phoneNumber, 'phoneNumber'),
      'reason': reason,
      'metadata': metadata,
    };
  }
}

class InitiateRechargeParams extends Params {
  const InitiateRechargeParams({
    required this.provider,
    required this.amount,
    required this.phoneNumber,
    this.reason,
    this.metadata,
  });

  final Provider provider;
  final num amount;
  final String phoneNumber;
  final String? reason;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() {
    _amount(amount);

    return {
      'provider': provider,
      'amount': amount,
      'phone_number': _phone(phoneNumber, 'phoneNumber'),
      'reason': reason,
      'metadata': metadata,
    };
  }
}

class CustomerParams extends Params {
  const CustomerParams({
    required this.fullName,
    this.email,
    this.phone,
    this.address,
    this.companyName,
    this.countryOfOrigin,
    this.city,
    this.metadata,
  });

  final String fullName;
  final String? email;
  final String? phone;
  final String? address;
  final String? companyName;
  final String? countryOfOrigin;
  final String? city;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() {
    if (fullName.trim().isEmpty) {
      throw InvalidArgumentException('"fullName" is required.');
    }

    return {
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'address': address,
      'company_name': companyName,
      'country_of_origin': countryOfOrigin,
      'city': city,
      'metadata': metadata,
    };
  }
}

class InvoiceItemParams extends Params {
  const InvoiceItemParams({
    required this.name,
    required this.unitPrice,
    this.quantity,
    this.description,
    this.taxRate,
    this.imageUrl,
    this.metadata,
  });

  final String name;
  final num unitPrice;
  final int? quantity;
  final String? description;
  final num? taxRate;
  final String? imageUrl;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() => {
        'name': name,
        'unit_price': unitPrice,
        'quantity': quantity,
        'description': description,
        'tax_rate': taxRate,
        'image_url': imageUrl,
        'metadata': metadata,
      };
}

class CreateInvoiceParams extends Params {
  const CreateInvoiceParams({
    required this.customer,
    required this.items,
    this.invoiceNumber,
    this.dueDate,
    this.notes,
    this.application,
    this.billingDetails,
    this.shippingDetails,
    this.metadata,
  });

  /// Customer id.
  final String customer;
  final List<InvoiceItemParams> items;
  final String? invoiceNumber;
  final DateTime? dueDate;
  final String? notes;
  final String? application;
  final Map<String, Object?>? billingDetails;
  final Map<String, Object?>? shippingDetails;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() {
    if (items.isEmpty) {
      throw InvalidArgumentException('An invoice needs at least one item.');
    }

    return _invoiceBody(
        customer, items, invoiceNumber, dueDate, notes, application, billingDetails, shippingDetails, metadata);
  }
}

class UpdateInvoiceParams extends Params {
  const UpdateInvoiceParams({
    this.customer,
    this.items,
    this.invoiceNumber,
    this.dueDate,
    this.notes,
    this.application,
    this.billingDetails,
    this.shippingDetails,
    this.metadata,
  });

  final String? customer;
  final List<InvoiceItemParams>? items;
  final String? invoiceNumber;
  final DateTime? dueDate;
  final String? notes;
  final String? application;
  final Map<String, Object?>? billingDetails;
  final Map<String, Object?>? shippingDetails;
  final Metadata? metadata;

  @override
  Map<String, Object?> toApi() => _invoiceBody(
      customer, items, invoiceNumber, dueDate, notes, application, billingDetails, shippingDetails, metadata);
}

Map<String, Object?> _invoiceBody(
  String? customer,
  List<InvoiceItemParams>? items,
  String? invoiceNumber,
  DateTime? dueDate,
  String? notes,
  String? application,
  Map<String, Object?>? billingDetails,
  Map<String, Object?>? shippingDetails,
  Metadata? metadata,
) =>
    {
      'customer': customer == null ? null : {'id': customer},
      'items': items?.map((i) => i.toApi()).toList(),
      'invoice_number': invoiceNumber,
      'due_date': dueDate,
      'notes': notes,
      'application': application,
      'billing_details': billingDetails,
      'shipping_details': shippingDetails,
      'metadata': metadata,
    };

/// Network and phone number for paying a checkout session or invoice.
class PayParams extends Params {
  const PayParams({required this.provider, required this.phoneNumber});

  final Provider provider;
  final String phoneNumber;

  @override
  Map<String, Object?> toApi() => {'provider': provider, 'phone_number': _phone(phoneNumber, 'phoneNumber')};
}

class PayInvoiceParams extends PayParams {
  const PayInvoiceParams({required super.provider, required super.phoneNumber, this.notes});

  final String? notes;

  @override
  Map<String, Object?> toApi() => {...super.toApi(), 'notes': notes};
}

class CreateWebhookEndpointParams extends Params {
  const CreateWebhookEndpointParams({this.url, this.isActive});

  /// Defaults to the client's `webhookUrl` option.
  final String? url;
  final bool? isActive;

  @override
  Map<String, Object?> toApi() => {'url': url, 'is_active': isActive};
}

class UpdateWebhookEndpointParams extends Params {
  const UpdateWebhookEndpointParams({this.url, this.isActive});

  final String? url;
  final bool? isActive;

  @override
  Map<String, Object?> toApi() => {'url': url, 'is_active': isActive};
}

/// Filters shared by every list call.
abstract class ListFilters extends Params {
  const ListFilters({this.page, this.limit});

  final int? page;
  final int? limit;

  @override
  Map<String, Object?> toApi() => {'page': page, 'limit': limit};
}

class ChargeListFilters extends ListFilters {
  const ChargeListFilters({
    super.page,
    super.limit,
    this.status,
    this.keyword,
    this.startDate,
    this.endDate,
    this.sortField,
    this.sortDirection,
  });

  final ChargeStatus? status;
  final String? keyword;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? sortField;
  final SortDirection? sortDirection;

  @override
  Map<String, Object?> toApi() => {
        ...super.toApi(),
        'status': status,
        'keyword': keyword,
        'start_date': startDate,
        'end_date': endDate,
        'sortField': sortField,
        'sortDirection': sortDirection,
      };
}

class PayoutListFilters extends ListFilters {
  const PayoutListFilters({
    super.page,
    super.limit,
    this.status,
    this.keyword,
    this.startDate,
    this.endDate,
    this.sortField,
    this.sortDirection,
  });

  final PayoutStatus? status;
  final String? keyword;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? sortField;
  final SortDirection? sortDirection;

  @override
  Map<String, Object?> toApi() => {
        ...super.toApi(),
        'status': status,
        'keyword': keyword,
        'start_date': startDate,
        'end_date': endDate,
        'sortField': sortField,
        'sortDirection': sortDirection,
      };
}

class RechargeListFilters extends ListFilters {
  const RechargeListFilters({super.page, super.limit, this.status, this.keyword, this.startDate, this.endDate});

  final RechargeStatus? status;
  final String? keyword;
  final DateTime? startDate;
  final DateTime? endDate;

  @override
  Map<String, Object?> toApi() => {
        ...super.toApi(),
        'status': status,
        'keyword': keyword,
        'start_date': startDate,
        'end_date': endDate,
      };
}

class InvoiceListFilters extends ListFilters {
  const InvoiceListFilters({
    super.page,
    super.limit,
    this.status,
    this.keyword,
    this.customer,
    this.startDate,
    this.endDate,
    this.sortField,
    this.sortDirection,
  });

  final InvoiceStatus? status;
  final String? keyword;
  final String? customer;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? sortField;
  final SortDirection? sortDirection;

  @override
  Map<String, Object?> toApi() => {
        ...super.toApi(),
        'status': status,
        'keyword': keyword,
        'customer': customer,
        'start_date': startDate,
        'end_date': endDate,
        'sortField': sortField,
        'sortDirection': sortDirection,
      };
}

class CustomerListFilters extends ListFilters {
  const CustomerListFilters({super.page, super.limit, this.keyword, this.isActive, this.sortField, this.sortDirection});

  final String? keyword;
  final bool? isActive;
  final String? sortField;
  final SortDirection? sortDirection;

  @override
  Map<String, Object?> toApi() => {
        ...super.toApi(),
        'keyword': keyword,
        'is_active': isActive,
        'sortField': sortField,
        'sortDirection': sortDirection,
      };
}

class BankFilters extends ListFilters {
  const BankFilters({required this.country, super.page, super.limit, this.keyword, this.name, this.swift});

  final String country;
  final String? keyword;
  final String? name;
  final String? swift;

  @override
  Map<String, Object?> toApi() =>
      {...super.toApi(), 'country': country, 'keyword': keyword, 'name': name, 'swift': swift};
}

class BankBranchFilters extends ListFilters {
  const BankBranchFilters({super.page, super.limit, this.code, this.swift, this.keyword});

  final String? code;
  final String? swift;
  final String? keyword;

  @override
  Map<String, Object?> toApi() {
    if (code == null && swift == null) {
      throw InvalidArgumentException('referenceData.bankBranches() needs a code or a swift filter.');
    }

    return {...super.toApi(), 'code': code, 'swift': swift, 'keyword': keyword};
  }
}

class CountryFilters extends ListFilters {
  const CountryFilters({super.page, super.limit, this.keyword, this.iso, this.currency, this.isSupported});

  final String? keyword;
  final String? iso;
  final String? currency;
  final bool? isSupported;

  @override
  Map<String, Object?> toApi() =>
      {...super.toApi(), 'keyword': keyword, 'iso': iso, 'currency': currency, 'is_supported': isSupported};
}

class CurrencyFilters extends ListFilters {
  const CurrencyFilters({super.page, super.limit, this.keyword, this.code, this.isSupported});

  final String? keyword;
  final String? code;
  final bool? isSupported;

  @override
  Map<String, Object?> toApi() => {...super.toApi(), 'keyword': keyword, 'code': code, 'is_supported': isSupported};
}

class ScopeFilters extends ListFilters {
  const ScopeFilters({super.page, super.limit, this.keyword});

  final String? keyword;

  @override
  Map<String, Object?> toApi() => {...super.toApi(), 'keyword': keyword};
}

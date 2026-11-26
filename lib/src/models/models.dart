import '../enums.dart';
import 'model.dart';

/// A request for money from a mobile money wallet.
class Charge extends Model {
  Charge(super.data)
      : id = str(data, 'id') ?? '',
        reference = str(data, 'reference'),
        amount = money(data, 'amount'),
        feeAmount = money(data, 'fee_amount'),
        netAmount = money(data, 'net_amount'),
        additionalFee = money(data, 'additional_fee'),
        currency = str(data, 'currency'),
        phoneNumber = str(data, 'phone_number'),
        provider = Provider.tryParse(data['provider']),
        status = ChargeStatus.tryParse(data['status']),
        reason = str(data, 'reason'),
        application = str(data, 'application'),
        notes = str(data, 'notes'),
        billingDetails = obj(data, 'billing_details'),
        shippingDetails = obj(data, 'shipping_details'),
        metadata = obj(data, 'metadata'),
        failureCode = str(data, 'failure_code'),
        failureMessage = str(data, 'failure_message'),
        expiresAt = date(data, 'expires_at'),
        createdAt = date(data, 'created_at');

  final String id;
  final String? reference;
  final num? amount;
  final num? feeAmount;
  final num? netAmount;
  final num? additionalFee;
  final String? currency;
  final String? phoneNumber;
  final Provider? provider;
  final ChargeStatus? status;
  final String? reason;
  final String? application;
  final String? notes;
  final Map<String, Object?>? billingDetails;
  final Map<String, Object?>? shippingDetails;
  final Map<String, Object?>? metadata;
  final String? failureCode;
  final String? failureMessage;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isPending => status == ChargeStatus.pending;
  bool get isSuccessful => status == ChargeStatus.successful;
  bool get isFinal => status?.isFinal ?? false;
}

class CheckoutSession extends Model {
  CheckoutSession(super.data)
      : id = str(data, 'id') ?? '',
        charge = relationId(data, 'charge'),
        reference = str(data, 'reference'),
        amount = money(data, 'amount'),
        feeAmount = money(data, 'fee_amount'),
        netAmount = money(data, 'net_amount'),
        currency = str(data, 'currency'),
        reason = str(data, 'reason'),
        phoneNumber = str(data, 'phone_number'),
        provider = Provider.tryParse(data['provider']),
        status = ChargeStatus.tryParse(data['status']),
        successUrl = str(data, 'success_url'),
        cancelUrl = str(data, 'cancel_url'),
        checkoutUrl = str(data, 'checkout_url'),
        token = str(data, 'token'),
        merchant = obj(data, 'merchant'),
        expiresAt = date(data, 'expires_at');

  final String id;
  final String? charge;
  final String? reference;
  final num? amount;
  final num? feeAmount;
  final num? netAmount;
  final String? currency;
  final String? reason;
  final String? phoneNumber;
  final Provider? provider;
  final ChargeStatus? status;
  final String? successUrl;
  final String? cancelUrl;
  final String? checkoutUrl;
  final String? token;
  final Map<String, Object?>? merchant;
  final DateTime? expiresAt;

  bool get isSuccessful => status == ChargeStatus.successful;
  bool get isFinal => status?.isFinal ?? false;

  /// The merchant's display name, when the API includes it.
  String? get merchantName => merchant == null ? null : (str(merchant!, 'name') ?? str(merchant!, 'business_name'));
}

class Payout extends Model {
  Payout(super.data)
      : id = str(data, 'id') ?? '',
        provider = Provider.tryParse(data['provider']),
        amount = money(data, 'amount'),
        feeAmount = money(data, 'fee_amount'),
        netAmount = money(data, 'net_amount'),
        currency = str(data, 'currency'),
        phoneNumber = str(data, 'phone_number'),
        reason = str(data, 'reason'),
        status = PayoutStatus.tryParse(data['status']),
        failureCode = str(data, 'failure_code'),
        failureMessage = str(data, 'failure_message'),
        approvedAt = date(data, 'approved_at'),
        scheduledAt = date(data, 'scheduled_at'),
        completedAt = date(data, 'completed_at'),
        expiresAt = date(data, 'expires_at'),
        createdAt = date(data, 'created_at');

  final String id;
  final Provider? provider;
  final num? amount;
  final num? feeAmount;
  final num? netAmount;
  final String? currency;
  final String? phoneNumber;
  final String? reason;
  final PayoutStatus? status;
  final String? failureCode;
  final String? failureMessage;
  final DateTime? approvedAt;
  final DateTime? scheduledAt;
  final DateTime? completedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isSuccessful => status == PayoutStatus.completed;
  bool get isFinal => status?.isFinal ?? false;
}

class Recharge extends Model {
  Recharge(super.data)
      : id = str(data, 'id') ?? '',
        reference = str(data, 'reference'),
        amount = money(data, 'amount'),
        feeAmount = money(data, 'fee_amount'),
        netAmount = money(data, 'net_amount'),
        phoneNumber = str(data, 'phone_number'),
        provider = Provider.tryParse(data['provider']),
        status = ChargeStatus.tryParse(data['status']),
        metadata = obj(data, 'metadata'),
        failureCode = str(data, 'failure_code'),
        failureMessage = str(data, 'failure_message'),
        createdAt = date(data, 'created_at');

  final String id;
  final String? reference;
  final num? amount;
  final num? feeAmount;
  final num? netAmount;
  final String? phoneNumber;
  final Provider? provider;
  final RechargeStatus? status;
  final Map<String, Object?>? metadata;
  final String? failureCode;
  final String? failureMessage;
  final DateTime? createdAt;

  bool get isSuccessful => status == ChargeStatus.successful;
  bool get isFinal => status?.isFinal ?? false;
}

class InvoiceItem extends Model {
  InvoiceItem(super.data)
      : id = str(data, 'id'),
        name = str(data, 'name'),
        description = str(data, 'description'),
        imageUrl = str(data, 'image_url'),
        quantity = integer(data, 'quantity'),
        unitPrice = money(data, 'unit_price'),
        amount = money(data, 'amount'),
        taxRate = money(data, 'tax_rate'),
        taxAmount = money(data, 'tax_amount');

  final String? id;
  final String? name;
  final String? description;
  final String? imageUrl;
  final int? quantity;
  final num? unitPrice;
  final num? amount;
  final num? taxRate;
  final num? taxAmount;
}

class Invoice extends Model {
  Invoice(super.data)
      : id = str(data, 'id') ?? '',
        invoiceNumber = str(data, 'invoice_number'),
        status = InvoiceStatus.tryParse(data['status']),
        customer = relationId(data, 'customer'),
        customerName = str(data, 'customer_name'),
        customerEmail = str(data, 'customer_email'),
        customerPhone = str(data, 'customer_phone'),
        subtotal = money(data, 'subtotal'),
        taxAmount = money(data, 'tax_amount'),
        discountAmount = money(data, 'discount_amount'),
        totalAmount = money(data, 'total_amount'),
        amountPaid = money(data, 'amount_paid'),
        feeAmount = money(data, 'fee_amount'),
        currency = str(data, 'currency'),
        notes = str(data, 'notes'),
        application = str(data, 'application'),
        metadata = obj(data, 'metadata'),
        items = List.unmodifiable(makeModels(InvoiceItem.new, data['items'])),
        merchant = obj(data, 'merchant'),
        issueDate = date(data, 'issue_date'),
        dueDate = date(data, 'due_date'),
        createdAt = date(data, 'created_at');

  final String id;
  final String? invoiceNumber;
  final InvoiceStatus? status;
  final String? customer;
  final String? customerName;
  final String? customerEmail;
  final String? customerPhone;
  final num? subtotal;
  final num? taxAmount;
  final num? discountAmount;
  final num? totalAmount;
  final num? amountPaid;
  final num? feeAmount;
  final String? currency;
  final String? notes;
  final String? application;
  final Map<String, Object?>? metadata;
  final List<InvoiceItem> items;
  final Map<String, Object?>? merchant;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? createdAt;

  bool get isPaid => status == InvoiceStatus.paid;
  bool get isFinal => status?.isFinal ?? false;

  /// What is still owed, when the API reports both totals.
  num? get amountDue => totalAmount == null ? null : totalAmount! - (amountPaid ?? 0);
}

class PaymentTransaction extends Model {
  PaymentTransaction(super.data)
      : id = str(data, 'id') ?? '',
        transactionId = str(data, 'transaction_id'),
        provider = Provider.tryParse(data['provider']),
        amount = money(data, 'amount'),
        feeAmount = money(data, 'fee_amount'),
        currency = str(data, 'currency'),
        customerPhone = str(data, 'customer_phone'),
        status = PaymentStatus.tryParse(data['status']),
        failureReason = str(data, 'failure_reason'),
        createdAt = date(data, 'created_at'),
        completedAt = date(data, 'completed_at');

  final String id;
  final String? transactionId;
  final Provider? provider;
  final num? amount;
  final num? feeAmount;
  final String? currency;
  final String? customerPhone;
  final PaymentStatus? status;
  final String? failureReason;
  final DateTime? createdAt;
  final DateTime? completedAt;

  bool get isSuccessful => status == PaymentStatus.successful;
  bool get isFinal => status?.isFinal ?? false;
}

/// Returned by `invoices.pay()`: the payment attempt that was started.
class PaymentInitiation extends Model {
  PaymentInitiation(super.data)
      : payment = obj(data, 'payment') == null ? null : PaymentTransaction(obj(data, 'payment')!),
        message = str(data, 'message'),
        instructions = str(data, 'instructions');

  final PaymentTransaction? payment;
  final String? message;
  final String? instructions;
}

class Customer extends Model {
  Customer(super.data)
      : id = str(data, 'id') ?? '',
        fullName = str(data, 'full_name'),
        email = str(data, 'email'),
        phone = str(data, 'phone'),
        address = str(data, 'address'),
        companyName = str(data, 'companyName') ?? str(data, 'company_name'),
        countryOfOrigin = str(data, 'countryOfOrigin') ?? str(data, 'country_of_origin'),
        city = str(data, 'city'),
        metadata = obj(data, 'metadata'),
        isActive = boolean(data, 'is_active'),
        createdAt = date(data, 'created_at');

  final String id;
  final String? fullName;
  final String? email;
  final String? phone;
  final String? address;
  final String? companyName;
  final String? countryOfOrigin;
  final String? city;
  final Map<String, Object?>? metadata;
  final bool? isActive;
  final DateTime? createdAt;
}

class WebhookEndpoint extends Model {
  WebhookEndpoint(super.data)
      : id = str(data, 'id') ?? '',
        url = str(data, 'url'),
        secret = str(data, 'secret'),
        isActive = boolean(data, 'is_active'),
        events = strings(data, 'events'),
        egressIps = strings(data, 'egress_ips'),
        signatureHeader = str(data, 'signature_header'),
        signatureAlgorithm = str(data, 'signature_algorithm'),
        createdAt = date(data, 'created_at');

  final String id;
  final String? url;

  /// Shown only when the endpoint is created or its secret rotated.
  final String? secret;
  final bool? isActive;
  final List<String> events;
  final List<String> egressIps;
  final String? signatureHeader;
  final String? signatureAlgorithm;
  final DateTime? createdAt;

  @override
  String toString() => 'WebhookEndpoint(id: $id, url: $url, secret: ${secret == null ? null : '****'})';
}

class WebhookTestResult extends Model {
  WebhookTestResult(super.data)
      : ok = boolean(data, 'ok') ?? false,
        statusCode = integer(data, 'status_code'),
        responseBody = str(data, 'response_body'),
        error = str(data, 'error');

  final bool ok;
  final int? statusCode;
  final String? responseBody;
  final String? error;
}

/// A live status change of a checkout session (from `checkout.watch()`).
class CheckoutUpdate extends Model {
  CheckoutUpdate(super.data)
      : checkout = str(data, 'checkout') ?? str(data, 'id'),
        charge = relationId(data, 'charge'),
        status = ChargeStatus.tryParse(data['status']),
        reference = str(data, 'reference'),
        successUrl = str(data, 'success_url'),
        cancelUrl = str(data, 'cancel_url');

  /// Builds an update from a full session (used by the polling fallback).
  factory CheckoutUpdate.fromSession(CheckoutSession session) => CheckoutUpdate({
        'checkout': session.id,
        'charge': session.charge,
        'status': session.raw['status'],
        'reference': session.reference,
        'success_url': session.successUrl,
        'cancel_url': session.cancelUrl,
      });

  final String? checkout;
  final String? charge;
  final ChargeStatus? status;
  final String? reference;
  final String? successUrl;
  final String? cancelUrl;

  bool get isSuccessful => status == ChargeStatus.successful;
  bool get isFinal => status?.isFinal ?? false;
}

/// A live status change of an invoice and its latest payment (from `invoices.watch()`).
class InvoiceUpdate extends Model {
  InvoiceUpdate(super.data)
      : invoice = str(data, 'invoice') ?? str(data, 'id'),
        invoiceNumber = str(data, 'invoice_number'),
        status = InvoiceStatus.tryParse(data['status']),
        paymentStatus = PaymentStatus.tryParse(data['payment_status']),
        transactionId = str(data, 'transaction_id'),
        amountPaid = money(data, 'amount_paid'),
        totalAmount = money(data, 'total_amount'),
        currency = str(data, 'currency');

  /// Builds an update from a full invoice (used by the polling fallback).
  factory InvoiceUpdate.fromInvoice(Invoice invoice) => InvoiceUpdate({
        'invoice': invoice.id,
        'invoice_number': invoice.invoiceNumber,
        'status': invoice.raw['status'],
        'amount_paid': invoice.amountPaid,
        'total_amount': invoice.totalAmount,
        'currency': invoice.currency,
      });

  final String? invoice;
  final String? invoiceNumber;
  final InvoiceStatus? status;
  final PaymentStatus? paymentStatus;
  final String? transactionId;
  final num? amountPaid;
  final num? totalAmount;
  final String? currency;

  bool get isPaid => status == InvoiceStatus.paid;
  bool get isFinal => status?.isFinal ?? false;
}

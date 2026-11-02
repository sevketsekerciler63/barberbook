import 'payment.dart';
import 'payment_transaction.dart';

/// Original payment plus append-only cash/debt movements. A refund returns
/// money and reduces the charge; it does not silently recreate customer debt.
class PaymentAccount {
  final Payment payment;
  final String customerName;
  final String? serviceName;
  final DateTime appointmentDate;
  final List<PaymentTransaction> transactions;

  PaymentAccount({
    required this.payment,
    required this.customerName,
    this.serviceName,
    required this.appointmentDate,
    required Iterable<PaymentTransaction> transactions,
  }) : transactions = List.unmodifiable(transactions);

  int get appointmentId => payment.appointmentId;
  int get collectionsCents => transactions
      .where((t) => t.type == PaymentTransactionType.collection)
      .fold(0, (sum, t) => sum + t.amountCents);
  int get refundedServiceCents => transactions
      .where((t) => t.type == PaymentTransactionType.refund)
      .fold(0, (sum, t) => sum + t.direction * t.serviceCents);
  int get refundedTipCents => transactions
      .where((t) => t.type == PaymentTransactionType.refund)
      .fold(0, (sum, t) => sum + t.direction * t.tipCents);
  int get waivedCents => transactions
      .where((t) => t.type == PaymentTransactionType.adjustment)
      .fold(0, (sum, t) => sum + t.direction * t.amountCents);
  int get grossCollectedCents =>
      (payment.status == PaymentStatus.paid ? payment.amountCents : 0) +
      collectionsCents;
  int get refundableServiceCents =>
      (grossCollectedCents - refundedServiceCents).clamp(0, 1 << 62);
  int get refundableTipCents =>
      ((payment.status == PaymentStatus.paid ? payment.tipCents : 0) -
              refundedTipCents)
          .clamp(0, 1 << 62);
  int get outstandingCents => payment.status == PaymentStatus.pending
      ? (payment.amountCents - collectionsCents - waivedCents).clamp(0, 1 << 62)
      : 0;
  bool get supportsCorrections =>
      payment.status == PaymentStatus.paid ||
      payment.status == PaymentStatus.pending;
}

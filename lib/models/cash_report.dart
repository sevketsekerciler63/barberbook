import 'payment.dart';
import 'payment_transaction.dart';

class CashReport {
  final int collectedCents;
  final int outstandingCents;
  final int discountCents;
  final int tipCents;
  final int collectionCount;
  final int refundedCents;
  final int refundedTipCents;
  final int waivedDebtCents;
  final int refundCount;
  final int reversedCollectionCents;
  final int collectionReversalCount;
  final Map<PaymentMethod, int> byMethod;

  const CashReport({
    required this.collectedCents,
    required this.outstandingCents,
    required this.discountCents,
    required this.tipCents,
    required this.collectionCount,
    this.refundedCents = 0,
    this.refundedTipCents = 0,
    this.waivedDebtCents = 0,
    this.refundCount = 0,
    this.reversedCollectionCents = 0,
    this.collectionReversalCount = 0,
    required this.byMethod,
  });

  int get netServiceCents =>
      collectedCents - refundedCents - reversedCollectionCents;
  int get netTipCents => tipCents - refundedTipCents;
  int get netCashCents => netServiceCents + netTipCents;

  factory CashReport.fromEntries({
    required Iterable<Payment> payments,
    required Iterable<PaymentTransaction> transactions,
    required int outstandingCents,
  }) {
    var collected = 0;
    var discount = 0;
    var tips = 0;
    var count = 0;
    var refunded = 0;
    var refundedTips = 0;
    var waived = 0;
    var refunds = 0;
    var reversedCollections = 0;
    var collectionReversals = 0;
    final byMethod = <PaymentMethod, int>{};

    for (final payment in payments) {
      if (payment.status != PaymentStatus.paid) continue;
      discount += payment.discountCents;
      tips += payment.tipCents;
      collected += payment.amountCents;
      count++;
      byMethod.update(
        payment.method,
        (value) => value + payment.amountCents,
        ifAbsent: () => payment.amountCents,
      );
    }

    for (final transaction in transactions) {
      if (transaction.type == PaymentTransactionType.adjustment) {
        waived += transaction.direction * transaction.amountCents;
        continue;
      }
      if (transaction.type == PaymentTransactionType.refund) {
        refunded += transaction.direction * transaction.serviceCents;
        refundedTips += transaction.direction * transaction.tipCents;
        refunds++;
        if (transaction.serviceCents != 0) {
          byMethod.update(
            transaction.method,
            (value) => value - transaction.direction * transaction.serviceCents,
            ifAbsent: () => -transaction.direction * transaction.serviceCents,
          );
        }
        continue;
      }
      if (transaction.reversesTransactionId != null) {
        reversedCollections += transaction.amountCents;
        collectionReversals++;
        byMethod.update(
          transaction.method,
          (value) => value - transaction.amountCents,
          ifAbsent: () => -transaction.amountCents,
        );
        continue;
      }
      collected += transaction.amountCents;
      count++;
      byMethod.update(
        transaction.method,
        (value) => value + transaction.amountCents,
        ifAbsent: () => transaction.amountCents,
      );
    }

    return CashReport(
      collectedCents: collected,
      outstandingCents: outstandingCents,
      discountCents: discount,
      tipCents: tips,
      collectionCount: count,
      refundedCents: refunded,
      refundedTipCents: refundedTips,
      waivedDebtCents: waived,
      refundCount: refunds,
      reversedCollectionCents: reversedCollections,
      collectionReversalCount: collectionReversals,
      byMethod: Map.unmodifiable(byMethod),
    );
  }
}

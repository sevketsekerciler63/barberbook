import 'payment.dart';
import 'payment_transaction.dart';

class CashReport {
  final int collectedCents;
  final int outstandingCents;
  final int discountCents;
  final int tipCents;
  final int collectionCount;
  final Map<PaymentMethod, int> byMethod;

  const CashReport({
    required this.collectedCents,
    required this.outstandingCents,
    required this.discountCents,
    required this.tipCents,
    required this.collectionCount,
    required this.byMethod,
  });

  factory CashReport.fromEntries({
    required Iterable<Payment> payments,
    required Iterable<PaymentTransaction> transactions,
    required int outstandingCents,
  }) {
    var collected = 0;
    var discount = 0;
    var tips = 0;
    var count = 0;
    final byMethod = <PaymentMethod, int>{};

    for (final payment in payments) {
      discount += payment.discountCents;
      tips += payment.tipCents;
      if (payment.status != PaymentStatus.paid) continue;
      collected += payment.amountCents;
      count++;
      byMethod.update(
        payment.method,
        (value) => value + payment.amountCents,
        ifAbsent: () => payment.amountCents,
      );
    }

    for (final transaction in transactions) {
      if (transaction.type != PaymentTransactionType.collection) continue;
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
      byMethod: Map.unmodifiable(byMethod),
    );
  }
}

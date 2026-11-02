import 'package:berber_randevu/models/cash_report.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/models/payment_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report combines direct payments and later credit collections', () {
    final report = CashReport.fromEntries(
      payments: [
        Payment(
          appointmentId: 1,
          amountCents: 50000,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          discountCents: 5000,
          tipCents: 3000,
          paidAt: DateTime(2026, 9, 21, 10),
        ),
        Payment(
          appointmentId: 2,
          amountCents: 40000,
          status: PaymentStatus.pending,
          method: PaymentMethod.credit,
        ),
      ],
      transactions: [
        PaymentTransaction(
          appointmentId: 2,
          type: PaymentTransactionType.collection,
          amountCents: 15000,
          method: PaymentMethod.card,
          occurredAt: DateTime(2026, 9, 21, 14),
        ),
      ],
      outstandingCents: 25000,
    );

    expect(report.collectedCents, 65000);
    expect(report.outstandingCents, 25000);
    expect(report.discountCents, 5000);
    expect(report.tipCents, 3000);
    expect(report.byMethod[PaymentMethod.cash], 50000);
    expect(report.byMethod[PaymentMethod.card], 15000);
    expect(report.byMethod.containsKey(PaymentMethod.credit), isFalse);
    expect(report.collectionCount, 2);
  });

  test('non-collection ledger entries do not count as cash income', () {
    final report = CashReport.fromEntries(
      payments: const [],
      transactions: [
        PaymentTransaction(
          appointmentId: 1,
          type: PaymentTransactionType.refund,
          amountCents: 10000,
          method: PaymentMethod.cash,
          occurredAt: DateTime(2026, 9, 21),
        ),
        PaymentTransaction(
          appointmentId: 1,
          type: PaymentTransactionType.adjustment,
          amountCents: 5000,
          method: PaymentMethod.other,
          occurredAt: DateTime(2026, 9, 21),
        ),
      ],
      outstandingCents: 0,
    );

    expect(report.collectedCents, 0);
    expect(report.collectionCount, 0);
    expect(report.byMethod, {PaymentMethod.cash: -10000});
    expect(report.refundedCents, 10000);
    expect(report.waivedDebtCents, 5000);
    expect(report.netCashCents, -10000);
  });
}

import 'package:berber_randevu/models/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('summary separates collected revenue and outstanding credit', () {
    final payments = [
      Payment(
        appointmentId: 1,
        amountCents: 50000,
        status: PaymentStatus.paid,
        method: PaymentMethod.cash,
      ),
      Payment(
        appointmentId: 2,
        amountCents: 75000,
        status: PaymentStatus.paid,
        method: PaymentMethod.card,
        tipCents: 5000,
      ),
      Payment(
        appointmentId: 3,
        amountCents: 30000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
      Payment(
        appointmentId: 4,
        amountCents: 90000,
        status: PaymentStatus.refunded,
        method: PaymentMethod.cash,
      ),
    ];

    final summary = PaymentSummary.fromPayments(payments);

    expect(summary.collectedCents, 125000);
    expect(summary.outstandingCents, 30000);
    expect(summary.tipCents, 5000);
    expect(summary.paidCount, 2);
    expect(summary.pendingCount, 1);
    expect(summary.byMethod[PaymentMethod.cash], 50000);
    expect(summary.byMethod[PaymentMethod.card], 75000);
  });
}

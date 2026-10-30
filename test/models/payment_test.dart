import 'package:berber_randevu/models/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paid payment round-trips money and method', () {
    final payment = Payment(
      id: 4,
      appointmentId: 12,
      amountCents: 75000,
      status: PaymentStatus.paid,
      method: PaymentMethod.cash,
      discountCents: 5000,
      tipCents: 1000,
      paidAt: DateTime(2026, 9, 21, 16, 30),
      note: 'İndirimli işlem',
      createdAt: DateTime(2026, 9, 21, 16, 30),
    );

    final restored = Payment.fromMap(payment.toMap());

    expect(restored.status, PaymentStatus.paid);
    expect(restored.method, PaymentMethod.cash);
    expect(restored.amountCents, 75000);
    expect(restored.discountCents, 5000);
    expect(restored.tipCents, 1000);
    expect(restored.isCollected, isTrue);
  });

  test('receivable payment is not included in collected revenue', () {
    final payment = Payment(
      appointmentId: 9,
      amountCents: 60000,
      status: PaymentStatus.pending,
      method: PaymentMethod.credit,
    );

    expect(payment.isCollected, isFalse);
    expect(payment.outstandingCents, 60000);
  });

  test('invalid negative money values are rejected', () {
    expect(
      () => Payment(
        appointmentId: 1,
        amountCents: -1,
        status: PaymentStatus.paid,
        method: PaymentMethod.card,
      ),
      throwsArgumentError,
    );
  });

  test('unknown stored values fall back safely', () {
    final payment = Payment.fromMap({
      'id': 1,
      'appointmentId': 2,
      'amountCents': 0,
      'status': 'future_status',
      'method': 'future_method',
      'discountCents': 0,
      'tipCents': 0,
      'paidAt': null,
      'note': null,
      'createdAt': '2026-09-21T16:00:00.000',
    });

    expect(payment.status, PaymentStatus.unknown);
    expect(payment.method, PaymentMethod.other);
  });
}

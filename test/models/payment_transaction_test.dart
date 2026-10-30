import 'package:berber_randevu/models/payment_transaction.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collection transaction round-trips without losing money metadata', () {
    final occurredAt = DateTime(2026, 9, 21, 16, 30);
    final transaction = PaymentTransaction(
      id: 7,
      appointmentId: 12,
      type: PaymentTransactionType.collection,
      amountCents: 25000,
      method: PaymentMethod.card,
      occurredAt: occurredAt,
      note: 'Kısmi tahsilat',
    );

    final restored = PaymentTransaction.fromMap(transaction.toMap());

    expect(restored.id, 7);
    expect(restored.appointmentId, 12);
    expect(restored.type, PaymentTransactionType.collection);
    expect(restored.amountCents, 25000);
    expect(restored.method, PaymentMethod.card);
    expect(restored.occurredAt, occurredAt);
    expect(restored.note, 'Kısmi tahsilat');
  });

  test('transaction rejects zero or negative amount', () {
    expect(
      () => PaymentTransaction(
        appointmentId: 1,
        type: PaymentTransactionType.collection,
        amountCents: 0,
        method: PaymentMethod.cash,
        occurredAt: DateTime(2026, 9, 21),
      ),
      throwsArgumentError,
    );
  });
}

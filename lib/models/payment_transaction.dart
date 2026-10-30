import 'payment.dart';

enum PaymentTransactionType { collection, refund, adjustment }

extension PaymentTransactionTypeCodec on PaymentTransactionType {
  String get value => switch (this) {
    PaymentTransactionType.collection => 'collection',
    PaymentTransactionType.refund => 'refund',
    PaymentTransactionType.adjustment => 'adjustment',
  };

  static PaymentTransactionType fromValue(String? value) => switch (value) {
    'refund' => PaymentTransactionType.refund,
    'adjustment' => PaymentTransactionType.adjustment,
    _ => PaymentTransactionType.collection,
  };
}

class PaymentTransaction {
  final int? id;
  final int appointmentId;
  final PaymentTransactionType type;
  final int amountCents;
  final PaymentMethod method;
  final DateTime occurredAt;
  final String? note;
  final DateTime createdAt;

  PaymentTransaction({
    this.id,
    required this.appointmentId,
    required this.type,
    required this.amountCents,
    required this.method,
    required this.occurredAt,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (amountCents <= 0) {
      throw ArgumentError('Kasa hareketi tutarı sıfırdan büyük olmalıdır.');
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'appointmentId': appointmentId,
    'type': type.value,
    'amountCents': amountCents,
    'method': method.value,
    'occurredAt': occurredAt.toIso8601String(),
    'note': note?.trim().isEmpty == true ? null : note?.trim(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory PaymentTransaction.fromMap(Map<String, dynamic> map) =>
      PaymentTransaction(
        id: map['id'] as int?,
        appointmentId: map['appointmentId'] as int,
        type: PaymentTransactionTypeCodec.fromValue(map['type'] as String?),
        amountCents: map['amountCents'] as int,
        method: PaymentMethodCodec.fromValue(map['method'] as String?),
        occurredAt: DateTime.parse(map['occurredAt'] as String),
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

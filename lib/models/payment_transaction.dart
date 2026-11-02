import 'payment.dart';
import 'dart:math';

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
  static String newOperationId() {
    final random = Random.secure();
    return 'correction-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  final int? id;
  final int appointmentId;
  final PaymentTransactionType type;
  final int amountCents;
  final int tipCents;
  final String? operationId;
  final int? reversesTransactionId;
  int get direction => reversesTransactionId == null ? 1 : -1;
  final PaymentMethod method;
  final DateTime occurredAt;
  final String? note;
  final DateTime createdAt;

  PaymentTransaction({
    this.id,
    required this.appointmentId,
    required this.type,
    required this.amountCents,
    this.tipCents = 0,
    this.operationId,
    this.reversesTransactionId,
    required this.method,
    required this.occurredAt,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (amountCents <= 0) {
      throw ArgumentError('Kasa hareketi tutarı sıfırdan büyük olmalıdır.');
    }
    if (tipCents < 0 ||
        tipCents > amountCents ||
        (type != PaymentTransactionType.refund && tipCents != 0)) {
      throw ArgumentError(
        'Bahşiş yalnız iade hareketinde, toplam tutarı aşmadan ayrılabilir.',
      );
    }
  }

  int get serviceCents => amountCents - tipCents;

  Map<String, dynamic> toMap() => {
    'id': id,
    'appointmentId': appointmentId,
    'type': type.value,
    'amountCents': amountCents,
    'tipCents': tipCents,
    'operationId': operationId,
    'reversesTransactionId': reversesTransactionId,
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
        tipCents: (map['tipCents'] as int?) ?? 0,
        operationId: map['operationId'] as String?,
        reversesTransactionId: map['reversesTransactionId'] as int?,
        method: PaymentMethodCodec.fromValue(map['method'] as String?),
        occurredAt: DateTime.parse(map['occurredAt'] as String),
        note: map['note'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

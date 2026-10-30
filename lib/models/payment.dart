enum PaymentStatus { unknown, pending, paid, refunded }

enum PaymentMethod { cash, card, transfer, credit, other }

extension PaymentStatusCodec on PaymentStatus {
  String get value => switch (this) {
    PaymentStatus.unknown => 'unknown',
    PaymentStatus.pending => 'pending',
    PaymentStatus.paid => 'paid',
    PaymentStatus.refunded => 'refunded',
  };

  static PaymentStatus fromValue(String? value) => switch (value) {
    'pending' => PaymentStatus.pending,
    'paid' => PaymentStatus.paid,
    'refunded' => PaymentStatus.refunded,
    _ => PaymentStatus.unknown,
  };
}

extension PaymentMethodCodec on PaymentMethod {
  String get value => switch (this) {
    PaymentMethod.cash => 'cash',
    PaymentMethod.card => 'card',
    PaymentMethod.transfer => 'transfer',
    PaymentMethod.credit => 'credit',
    PaymentMethod.other => 'other',
  };

  String get label => switch (this) {
    PaymentMethod.cash => 'Nakit',
    PaymentMethod.card => 'Kart',
    PaymentMethod.transfer => 'FAST / Havale',
    PaymentMethod.credit => 'Veresiye',
    PaymentMethod.other => 'Diğer',
  };

  static PaymentMethod fromValue(String? value) => switch (value) {
    'cash' => PaymentMethod.cash,
    'card' => PaymentMethod.card,
    'transfer' => PaymentMethod.transfer,
    'credit' => PaymentMethod.credit,
    _ => PaymentMethod.other,
  };
}

class PaymentSummary {
  final int collectedCents;
  final int outstandingCents;
  final int tipCents;
  final int paidCount;
  final int pendingCount;
  final Map<PaymentMethod, int> byMethod;

  const PaymentSummary({
    required this.collectedCents,
    required this.outstandingCents,
    required this.tipCents,
    required this.paidCount,
    required this.pendingCount,
    required this.byMethod,
  });

  factory PaymentSummary.fromPayments(Iterable<Payment> payments) {
    var collected = 0;
    var outstanding = 0;
    var tips = 0;
    var paidCount = 0;
    var pendingCount = 0;
    final byMethod = <PaymentMethod, int>{};

    for (final payment in payments) {
      if (payment.status == PaymentStatus.paid) {
        collected += payment.amountCents;
        tips += payment.tipCents;
        paidCount++;
        byMethod.update(
          payment.method,
          (value) => value + payment.amountCents,
          ifAbsent: () => payment.amountCents,
        );
      } else if (payment.status == PaymentStatus.pending) {
        outstanding += payment.amountCents;
        pendingCount++;
      }
    }

    return PaymentSummary(
      collectedCents: collected,
      outstandingCents: outstanding,
      tipCents: tips,
      paidCount: paidCount,
      pendingCount: pendingCount,
      byMethod: Map.unmodifiable(byMethod),
    );
  }
}

class Payment {
  final int? id;
  final int appointmentId;
  final int amountCents;
  final PaymentStatus status;
  final PaymentMethod method;
  final int discountCents;
  final int tipCents;
  final DateTime? paidAt;
  final String? note;
  final DateTime createdAt;

  Payment({
    this.id,
    required this.appointmentId,
    required this.amountCents,
    required this.status,
    required this.method,
    this.discountCents = 0,
    this.tipCents = 0,
    this.paidAt,
    this.note,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (amountCents < 0 || discountCents < 0 || tipCents < 0) {
      throw ArgumentError('Parasal değerler negatif olamaz.');
    }
  }

  bool get isCollected => status == PaymentStatus.paid;
  int get outstandingCents => status == PaymentStatus.pending ? amountCents : 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'appointmentId': appointmentId,
    'amountCents': amountCents,
    'status': status.value,
    'method': method.value,
    'discountCents': discountCents,
    'tipCents': tipCents,
    'paidAt': paidAt?.toIso8601String(),
    'note': note?.trim().isEmpty == true ? null : note?.trim(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Payment.fromMap(Map<String, dynamic> map) => Payment(
    id: map['id'] as int?,
    appointmentId: map['appointmentId'] as int,
    amountCents: (map['amountCents'] as int?) ?? 0,
    status: PaymentStatusCodec.fromValue(map['status'] as String?),
    method: PaymentMethodCodec.fromValue(map['method'] as String?),
    discountCents: (map['discountCents'] as int?) ?? 0,
    tipCents: (map['tipCents'] as int?) ?? 0,
    paidAt: map['paidAt'] == null
        ? null
        : DateTime.parse(map['paidAt'] as String),
    note: map['note'] as String?,
    createdAt: map['createdAt'] == null
        ? DateTime.now()
        : DateTime.parse(map['createdAt'] as String),
  );
}

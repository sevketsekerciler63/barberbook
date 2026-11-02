class Receivable {
  final int appointmentId;
  final String customerName;
  final String? serviceName;
  final DateTime appointmentDate;
  final int originalAmountCents;
  final int collectedCents;
  final int outstandingCents;
  final int refundedCents;
  final int waivedCents;

  const Receivable({
    required this.appointmentId,
    required this.customerName,
    required this.serviceName,
    required this.appointmentDate,
    required this.originalAmountCents,
    required this.collectedCents,
    required this.outstandingCents,
    this.refundedCents = 0,
    this.waivedCents = 0,
  });

  factory Receivable.fromMap(Map<String, dynamic> map) => Receivable(
    appointmentId: map['appointmentId'] as int,
    customerName: map['customerName'] as String,
    serviceName: map['serviceName'] as String?,
    appointmentDate: DateTime.parse(map['appointmentDate'] as String),
    originalAmountCents: map['originalAmountCents'] as int,
    collectedCents: map['collectedCents'] as int,
    outstandingCents: map['outstandingCents'] as int,
    refundedCents: (map['refundedCents'] as int?) ?? 0,
    waivedCents: (map['waivedCents'] as int?) ?? 0,
  );
}

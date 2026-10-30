enum AppointmentStatus { planned, completed, cancelled, noShow }

bool appointmentsOverlap(Appointment first, Appointment second) {
  if (!first.isActive || !second.isActive) return false;
  final sameDay =
      first.appointmentDate.year == second.appointmentDate.year &&
      first.appointmentDate.month == second.appointmentDate.month &&
      first.appointmentDate.day == second.appointmentDate.day;
  if (!sameDay) return false;

  return first.fullDateTime.isBefore(second.endDateTime) &&
      second.fullDateTime.isBefore(first.endDateTime);
}

/// Returns true when adding [candidate] exceeds the parallel capacity at any
/// point in its interval. End boundaries are non-overlapping.
bool appointmentExceedsCapacity(
  Appointment candidate,
  Iterable<Appointment> existing, {
  required int capacity,
}) {
  if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  if (!candidate.isActive) return false;

  final events = <({DateTime time, int delta})>[
    (time: candidate.fullDateTime, delta: 1),
    (time: candidate.endDateTime, delta: -1),
  ];
  for (final appointment in existing) {
    if (!appointment.isActive || !appointmentsOverlap(appointment, candidate)) {
      continue;
    }
    events.add((time: appointment.fullDateTime, delta: 1));
    events.add((time: appointment.endDateTime, delta: -1));
  }
  events.sort((left, right) {
    final byTime = left.time.compareTo(right.time);
    return byTime != 0 ? byTime : left.delta.compareTo(right.delta);
  });

  var concurrent = 0;
  for (final event in events) {
    concurrent += event.delta;
    if (concurrent > capacity) return true;
  }
  return false;
}

extension AppointmentStatusCodec on AppointmentStatus {
  String get value => switch (this) {
    AppointmentStatus.planned => 'planned',
    AppointmentStatus.completed => 'completed',
    AppointmentStatus.cancelled => 'cancelled',
    AppointmentStatus.noShow => 'no_show',
  };

  static AppointmentStatus fromValue(String? value) => switch (value) {
    'completed' => AppointmentStatus.completed,
    'cancelled' => AppointmentStatus.cancelled,
    'no_show' => AppointmentStatus.noShow,
    _ => AppointmentStatus.planned,
  };
}

class Appointment {
  final int? id;
  final int? customerId;
  final String customerName;
  final DateTime appointmentDate;
  final String appointmentTime; // HH:mm format
  final String? hairstyleId;
  final String? hairstyleName;
  final int? serviceId;
  final String? serviceName;
  final int durationMinutes;
  final int? priceCents;
  final String? notes;
  final AppointmentStatus status;
  final DateTime createdAt;

  bool get isCompleted => status == AppointmentStatus.completed;
  bool get isActive => status == AppointmentStatus.planned;
  bool get shouldHaveAlarm => isActive;

  Appointment({
    this.id,
    this.customerId,
    required this.customerName,
    required this.appointmentDate,
    required this.appointmentTime,
    this.hairstyleId,
    this.hairstyleName,
    this.serviceId,
    this.serviceName,
    this.durationMinutes = 30,
    this.priceCents,
    this.notes,
    bool isCompleted = false,
    AppointmentStatus? status,
    DateTime? createdAt,
  }) : status =
           status ??
           (isCompleted
               ? AppointmentStatus.completed
               : AppointmentStatus.planned),
       createdAt = createdAt ?? DateTime.now();

  /// Returns the full DateTime of the appointment (date + time combined)
  DateTime get fullDateTime {
    final parts = appointmentTime.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
      hour,
      minute,
    );
  }

  DateTime get endDateTime =>
      fullDateTime.add(Duration(minutes: durationMinutes));

  AppointmentRepeatTemplate get repeatTemplate => AppointmentRepeatTemplate(
    customerId: customerId,
    customerName: customerName,
    hairstyleId: hairstyleId,
    hairstyleName: hairstyleName,
    serviceId: serviceId,
    serviceName: serviceName,
    durationMinutes: durationMinutes,
    priceCents: priceCents,
    notes: notes,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerId': customerId,
      'customerName': customerName,
      'appointmentDate': appointmentDate.toIso8601String(),
      'appointmentTime': appointmentTime,
      'hairstyleId': hairstyleId,
      'hairstyleName': hairstyleName,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'durationMinutes': durationMinutes,
      'priceCents': priceCents,
      'notes': notes,
      'isCompleted': isCompleted ? 1 : 0,
      'status': status.value,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Appointment.fromMap(Map<String, dynamic> map) {
    final storedStatus = map['status'] as String?;
    final legacyCompleted = (map['isCompleted'] as int?) == 1;
    return Appointment(
      id: map['id'] as int?,
      customerId: map['customerId'] as int?,
      customerName: map['customerName'] as String,
      appointmentDate: DateTime.parse(map['appointmentDate'] as String),
      appointmentTime: map['appointmentTime'] as String,
      hairstyleId: map['hairstyleId'] as String?,
      hairstyleName: map['hairstyleName'] as String?,
      serviceId: map['serviceId'] as int?,
      serviceName: map['serviceName'] as String?,
      durationMinutes: (map['durationMinutes'] as int?) ?? 30,
      priceCents: map['priceCents'] as int?,
      notes: map['notes'] as String?,
      status: storedStatus == null
          ? (legacyCompleted
                ? AppointmentStatus.completed
                : AppointmentStatus.planned)
          : AppointmentStatusCodec.fromValue(storedStatus),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Appointment copyWith({
    int? id,
    int? customerId,
    String? customerName,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? hairstyleId,
    String? hairstyleName,
    int? serviceId,
    String? serviceName,
    int? durationMinutes,
    int? priceCents,
    String? notes,
    bool? isCompleted,
    AppointmentStatus? status,
    DateTime? createdAt,
  }) {
    return Appointment(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
      hairstyleId: hairstyleId ?? this.hairstyleId,
      hairstyleName: hairstyleName ?? this.hairstyleName,
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      priceCents: priceCents ?? this.priceCents,
      notes: notes ?? this.notes,
      status:
          status ??
          (isCompleted == null
              ? this.status
              : isCompleted
              ? AppointmentStatus.completed
              : AppointmentStatus.planned),
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class AppointmentRepeatTemplate {
  const AppointmentRepeatTemplate({
    required this.customerId,
    required this.customerName,
    required this.hairstyleId,
    required this.hairstyleName,
    required this.serviceId,
    required this.serviceName,
    required this.durationMinutes,
    required this.priceCents,
    required this.notes,
  });

  final int? customerId;
  final String customerName;
  final String? hairstyleId;
  final String? hairstyleName;
  final int? serviceId;
  final String? serviceName;
  final int durationMinutes;
  final int? priceCents;
  final String? notes;
  String? get appointmentTime => null;
  AppointmentStatus get status => AppointmentStatus.planned;
  int? get id => null;
}

import 'appointment.dart';

class WorkingInterval {
  final int? id;
  final int weekday;
  final int startMinute;
  final int endMinute;

  WorkingInterval({
    this.id,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  }) {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday');
    }
    if (startMinute < 0 || startMinute > 1439) {
      throw ArgumentError.value(startMinute, 'startMinute');
    }
    if (endMinute < 1 || endMinute > 1440 || startMinute >= endMinute) {
      throw ArgumentError.value(endMinute, 'endMinute');
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory WorkingInterval.fromMap(Map<String, dynamic> map) => WorkingInterval(
    id: map['id'] as int?,
    weekday: map['weekday'] as int,
    startMinute: map['startMinute'] as int,
    endMinute: map['endMinute'] as int,
  );
}

class ClosedTimeBlock {
  final int? id;
  final DateTime startAt;
  final DateTime endAt;
  final String? reason;
  final DateTime createdAt;

  ClosedTimeBlock({
    this.id,
    required this.startAt,
    required this.endAt,
    this.reason,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now() {
    if (!startAt.isBefore(endAt)) {
      throw ArgumentError('Kapalı zaman başlangıcı bitişten önce olmalıdır.');
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'reason': reason,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ClosedTimeBlock.fromMap(Map<String, dynamic> map) => ClosedTimeBlock(
    id: map['id'] as int?,
    startAt: DateTime.parse(map['startAt'] as String),
    endAt: DateTime.parse(map['endAt'] as String),
    reason: map['reason'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}

bool isInsideWorkingHours(
  Appointment appointment,
  List<WorkingInterval> intervals,
) {
  final weekday = appointment.fullDateTime.weekday;
  final start =
      appointment.fullDateTime.hour * 60 + appointment.fullDateTime.minute;
  final end = start + appointment.durationMinutes;
  return intervals.any(
    (interval) =>
        interval.weekday == weekday &&
        start >= interval.startMinute &&
        end <= interval.endMinute,
  );
}

bool overlapsClosedTime(Appointment appointment, ClosedTimeBlock block) =>
    appointment.fullDateTime.isBefore(block.endAt) &&
    block.startAt.isBefore(appointment.endDateTime);

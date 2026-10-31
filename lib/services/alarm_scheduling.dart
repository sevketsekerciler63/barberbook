import '../models/appointment.dart';

enum AlarmScheduleResult { scheduled, notRequired, failed }

/// The native plugin replaces alarms in the same second. Allocate a free second
/// within the booked minute so parallel-capacity appointments retain every alarm.
DateTime availableNativeAlarmTime(
  DateTime desired,
  Iterable<DateTime> occupied,
) {
  final seconds = occupied
      .map((time) => time.millisecondsSinceEpoch ~/ 1000)
      .toSet();
  for (var offset = 0; offset < 60; offset++) {
    final candidate = desired.add(Duration(seconds: offset));
    if (!seconds.contains(candidate.millisecondsSinceEpoch ~/ 1000)) {
      return candidate;
    }
  }
  throw StateError('Bu dakika için boş alarm zamanı kalmadı.');
}

Future<AlarmScheduleResult> attemptAppointmentAlarm({
  required Appointment appointment,
  required DateTime now,
  required Future<bool> Function(Appointment) schedule,
}) async {
  if (!appointment.shouldHaveAlarm || !appointment.fullDateTime.isAfter(now)) {
    return AlarmScheduleResult.notRequired;
  }
  if (appointment.id == null) return AlarmScheduleResult.failed;
  try {
    return await schedule(appointment)
        ? AlarmScheduleResult.scheduled
        : AlarmScheduleResult.failed;
  } catch (_) {
    return AlarmScheduleResult.failed;
  }
}

import '../models/appointment.dart';

/// Replaces the device's scheduled alarms with the current appointment snapshot.
/// Load the snapshot before calling this so a database error cannot erase alarms.
Future<void> rebuildAppointmentAlarms({
  required Iterable<Appointment> appointments,
  required DateTime now,
  required Future<void> Function() cancelAll,
  required Future<bool> Function(Appointment) schedule,
}) async {
  final upcoming = appointments
      .where(
        (appointment) =>
            appointment.id != null &&
            appointment.shouldHaveAlarm &&
            appointment.fullDateTime.isAfter(now),
      )
      .toList();
  await cancelAll();
  var failures = 0;
  for (final appointment in upcoming) {
    try {
      if (!await schedule(appointment)) failures++;
    } catch (_) {
      failures++;
    }
  }
  if (failures > 0) {
    throw StateError('$failures randevu alarmı yeniden kurulamadı.');
  }
}

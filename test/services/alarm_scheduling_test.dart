import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/services/alarm_scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'same-minute appointments get distinct native seconds and never spill into next minute',
    () {
      final base = DateTime(2026, 10, 31, 10);
      expect(
        availableNativeAlarmTime(base, [base]),
        base.add(const Duration(seconds: 1)),
      );
      expect(
        availableNativeAlarmTime(base, [base.add(const Duration(seconds: 1))]),
        base,
      );
      final full = [
        for (var second = 0; second < 60; second++)
          base.add(Duration(seconds: second)),
      ];
      expect(() => availableNativeAlarmTime(base, full), throwsStateError);
    },
  );
  final now = DateTime(2026, 10, 31, 9);
  final appointment = Appointment(
    id: 1,
    customerName: 'Test',
    appointmentDate: now,
    appointmentTime: '10:00',
  );
  test(
    'native false and exception remain failures rather than successful saves',
    () async {
      expect(
        await attemptAppointmentAlarm(
          appointment: appointment,
          now: now,
          schedule: (_) async => false,
        ),
        AlarmScheduleResult.failed,
      );
      expect(
        await attemptAppointmentAlarm(
          appointment: appointment,
          now: now,
          schedule: (_) async => throw StateError('permission'),
        ),
        AlarmScheduleResult.failed,
      );
      expect(
        await attemptAppointmentAlarm(
          appointment: appointment,
          now: now,
          schedule: (_) async => true,
        ),
        AlarmScheduleResult.scheduled,
      );
    },
  );
  test(
    'past and inactive appointments do not request native scheduling',
    () async {
      var calls = 0;
      Future<bool> schedule(Appointment _) async {
        calls++;
        return true;
      }

      expect(
        await attemptAppointmentAlarm(
          appointment: appointment,
          now: now.add(const Duration(days: 1)),
          schedule: schedule,
        ),
        AlarmScheduleResult.notRequired,
      );
      expect(
        await attemptAppointmentAlarm(
          appointment: appointment.copyWith(
            status: AppointmentStatus.cancelled,
          ),
          now: now,
          schedule: schedule,
        ),
        AlarmScheduleResult.notRequired,
      );
      expect(calls, 0);
    },
  );
}

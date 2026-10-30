import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/working_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('working interval validates weekday and minute bounds', () {
    expect(
      () => WorkingInterval(weekday: 0, startMinute: 540, endMinute: 1080),
      throwsArgumentError,
    );
    expect(
      () => WorkingInterval(weekday: 1, startMinute: 600, endMinute: 600),
      throwsArgumentError,
    );
  });

  test('appointment must fit completely inside one working interval', () {
    final appointment = Appointment(
      customerName: 'Ali',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '12:30',
      durationMinutes: 45,
    );
    final intervals = [
      WorkingInterval(weekday: 1, startMinute: 540, endMinute: 780),
      WorkingInterval(weekday: 1, startMinute: 840, endMinute: 1080),
    ];

    expect(isInsideWorkingHours(appointment, intervals), isFalse);
    expect(
      isInsideWorkingHours(
        appointment.copyWith(appointmentTime: '11:30'),
        intervals,
      ),
      isTrue,
    );
  });

  test('closed block uses half-open interval overlap', () {
    final appointment = Appointment(
      customerName: 'Ali',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '10:00',
      durationMinutes: 30,
    );
    final touching = ClosedTimeBlock(
      startAt: DateTime(2026, 9, 21, 10, 30),
      endAt: DateTime(2026, 9, 21, 11),
    );
    final overlapping = ClosedTimeBlock(
      startAt: DateTime(2026, 9, 21, 10, 15),
      endAt: DateTime(2026, 9, 21, 10, 45),
    );

    expect(overlapsClosedTime(appointment, touching), isFalse);
    expect(overlapsClosedTime(appointment, overlapping), isTrue);
  });
}

import 'package:berber_randevu/models/appointment.dart';
import 'package:flutter_test/flutter_test.dart';

Appointment appointmentAt(
  String time, {
  int durationMinutes = 30,
  AppointmentStatus status = AppointmentStatus.planned,
}) => Appointment(
  customerName: 'Test',
  appointmentDate: DateTime(2026, 9, 21),
  appointmentTime: time,
  durationMinutes: durationMinutes,
  status: status,
);

void main() {
  test('overlapping active appointment intervals conflict', () {
    expect(
      appointmentsOverlap(
        appointmentAt('10:00', durationMinutes: 45),
        appointmentAt('10:30', durationMinutes: 30),
      ),
      isTrue,
    );
  });

  test('touching interval boundaries do not conflict', () {
    expect(
      appointmentsOverlap(
        appointmentAt('10:00', durationMinutes: 30),
        appointmentAt('10:30', durationMinutes: 30),
      ),
      isFalse,
    );
  });

  test('cancelled and no-show appointments release their interval', () {
    expect(
      appointmentsOverlap(
        appointmentAt(
          '10:00',
          durationMinutes: 45,
          status: AppointmentStatus.cancelled,
        ),
        appointmentAt('10:15'),
      ),
      isFalse,
    );
    expect(
      appointmentsOverlap(
        appointmentAt('10:00', status: AppointmentStatus.noShow),
        appointmentAt('10:00'),
      ),
      isFalse,
    );
  });

  test('capacity permits a second overlap but rejects a third', () {
    final existing = [
      appointmentAt('10:00', durationMinutes: 60),
      appointmentAt('10:15', durationMinutes: 30),
    ];

    expect(
      appointmentExceedsCapacity(
        appointmentAt('10:30'),
        existing.take(1),
        capacity: 2,
      ),
      isFalse,
    );
    expect(
      appointmentExceedsCapacity(appointmentAt('10:30'), existing, capacity: 2),
      isTrue,
    );
  });

  test('inactive appointments do not consume capacity', () {
    expect(
      appointmentExceedsCapacity(appointmentAt('10:00'), [
        appointmentAt('10:00', status: AppointmentStatus.cancelled),
      ], capacity: 1),
      isFalse,
    );
  });
}

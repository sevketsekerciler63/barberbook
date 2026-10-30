import 'package:flutter_test/flutter_test.dart';
import 'package:berber_randevu/models/appointment.dart';

void main() {
  test('appointment status defaults to planned', () {
    final appointment = Appointment(
      customerName: 'Ayşe',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '10:00',
    );

    expect(appointment.status, AppointmentStatus.planned);
    expect(appointment.toMap()['status'], 'planned');
  });

  test('completed status is the source of truth for legacy completion', () {
    final completed = Appointment(
      customerName: 'Zeynep',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '12:00',
      status: AppointmentStatus.completed,
    );
    final cancelled = completed.copyWith(status: AppointmentStatus.cancelled);

    expect(completed.isCompleted, isTrue);
    expect(completed.toMap()['isCompleted'], 1);
    expect(cancelled.isCompleted, isFalse);
    expect(cancelled.toMap()['isCompleted'], 0);
  });

  test('legacy completion flag restores completed status', () {
    final restored = Appointment.fromMap({
      'id': 1,
      'customerId': null,
      'customerName': 'Ali',
      'appointmentDate': DateTime(2026, 9, 21).toIso8601String(),
      'appointmentTime': '13:00',
      'hairstyleId': null,
      'hairstyleName': null,
      'notes': null,
      'isCompleted': 1,
      'createdAt': DateTime(2026, 9, 20).toIso8601String(),
    });

    expect(restored.status, AppointmentStatus.completed);
    expect(restored.isCompleted, isTrue);
  });

  test(
    'cancelled and no-show statuses round-trip without becoming completed',
    () {
      for (final status in [
        AppointmentStatus.cancelled,
        AppointmentStatus.noShow,
      ]) {
        final appointment = Appointment(
          customerName: 'Ali',
          appointmentDate: DateTime(2026, 9, 21),
          appointmentTime: '14:00',
          status: status,
        );

        final restored = Appointment.fromMap(appointment.toMap());
        expect(restored.status, status);
        expect(restored.isCompleted, isFalse);
      }
    },
  );

  test('unknown stored statuses safely fall back to planned', () {
    expect(
      AppointmentStatusCodec.fromValue('future_status'),
      AppointmentStatus.planned,
    );
  });

  test('only planned appointments are active and alarm eligible', () {
    Appointment appointmentWith(AppointmentStatus status) => Appointment(
      customerName: 'Ali',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '14:00',
      status: status,
    );

    expect(appointmentWith(AppointmentStatus.planned).isActive, isTrue);
    expect(appointmentWith(AppointmentStatus.planned).shouldHaveAlarm, isTrue);
    expect(appointmentWith(AppointmentStatus.completed).isActive, isFalse);
    expect(
      appointmentWith(AppointmentStatus.cancelled).shouldHaveAlarm,
      isFalse,
    );
    expect(appointmentWith(AppointmentStatus.noShow).shouldHaveAlarm, isFalse);
  });

  test('appointment exposes a duration based end time', () {
    final appointment = Appointment(
      customerName: 'Ali',
      appointmentDate: DateTime(2026, 9, 21),
      appointmentTime: '14:00',
      durationMinutes: 45,
      serviceId: 2,
      serviceName: 'Saç + Sakal',
      priceCents: 75000,
    );

    expect(appointment.endDateTime, DateTime(2026, 9, 21, 14, 45));
    expect(appointment.toMap()['durationMinutes'], 45);
    expect(appointment.toMap()['serviceName'], 'Saç + Sakal');
    expect(appointment.toMap()['priceCents'], 75000);
  });
}

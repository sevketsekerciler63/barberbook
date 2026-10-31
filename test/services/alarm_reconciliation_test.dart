import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/services/alarm_reconciliation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 31, 10);
  Appointment appointment(
    int? id,
    String time, {
    AppointmentStatus status = AppointmentStatus.planned,
  }) => Appointment(
    id: id,
    customerName: 'Deneme',
    appointmentDate: now,
    appointmentTime: time,
    status: status,
  );

  test(
    'restore replaces stale alarms and schedules only future planned records',
    () async {
      final device = <int>{99};
      var cancellations = 0;
      await rebuildAppointmentAlarms(
        appointments: [
          appointment(1, '11:00'),
          appointment(2, '09:00'),
          appointment(3, '10:00'),
          appointment(4, '12:00', status: AppointmentStatus.completed),
          appointment(5, '12:00', status: AppointmentStatus.cancelled),
          appointment(6, '12:00', status: AppointmentStatus.noShow),
          appointment(null, '12:00'),
        ],
        now: now,
        cancelAll: () async {
          cancellations++;
          device.clear();
        },
        schedule: (a) async {
          device.add(a.id!);
          return true;
        },
      );
      expect(device, {1});
      expect(cancellations, 1);
    },
  );
  test('empty restored schedule clears all old alarms', () async {
    var cancelled = false;
    await rebuildAppointmentAlarms(
      appointments: [],
      now: now,
      cancelAll: () async {
        cancelled = true;
      },
      schedule: (_) async => fail('No new alarms expected'),
    );
    expect(cancelled, isTrue);
  });
  test(
    'failed scheduling is reported and does not skip remaining records',
    () async {
      final attempted = <int>[];
      await expectLater(
        rebuildAppointmentAlarms(
          appointments: [
            appointment(1, '11:00'),
            appointment(2, '12:00'),
            appointment(3, '13:00'),
          ],
          now: now,
          cancelAll: () async {},
          schedule: (a) async {
            attempted.add(a.id!);
            if (a.id == 1) throw StateError('native failure');
            return a.id != 2;
          },
        ),
        throwsStateError,
      );
      expect(attempted, [1, 2, 3]);
    },
  );
  test(
    'failure cancelling old alarms prevents adding a conflicting new set',
    () async {
      await expectLater(
        rebuildAppointmentAlarms(
          appointments: [appointment(1, '11:00')],
          now: now,
          cancelAll: () async => throw StateError('native failure'),
          schedule: (_) async => fail('Must cancel before scheduling'),
        ),
        throwsStateError,
      );
    },
  );
}

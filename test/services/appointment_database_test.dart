import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/services/database_service.dart';
import '../test_helpers/database_test_isolation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final isolation = DatabaseTestIsolation();

  setUp(isolation.setUp);

  tearDown(isolation.tearDown);

  test(
    'appointment capacity defaults to one and releases cancelled slots',
    () async {
      final service = DatabaseService.instance;
      expect(await service.getAppointmentCapacity(), 1);

      final date = DateTime(2026, 9, 21);
      final firstId = await service.insertAppointment(
        Appointment(
          customerName: 'İlk',
          appointmentDate: date,
          appointmentTime: '10:00',
        ),
      );
      expect(await service.isTimeSlotTaken(date, '10:00'), isTrue);

      await service.setAppointmentCapacity(2);
      expect(await service.isTimeSlotTaken(date, '10:00'), isFalse);
      await service.insertAppointment(
        Appointment(
          customerName: 'İkinci',
          appointmentDate: date,
          appointmentTime: '10:00',
        ),
      );
      expect(await service.isTimeSlotTaken(date, '10:00'), isTrue);

      await service.setAppointmentStatus(firstId, AppointmentStatus.cancelled);
      expect(await service.isTimeSlotTaken(date, '10:00'), isFalse);
    },
  );

  test('no-show status persists and releases the upcoming list', () async {
    final db = await DatabaseService.instance.database;
    final id = await db.insert('appointments', {
      'customerName': 'Gelmedi Testi',
      'appointmentDate': DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String(),
      'appointmentTime': '14:00',
      'durationMinutes': 30,
      'isCompleted': 0,
      'status': 'planned',
      'createdAt': DateTime.now().toIso8601String(),
    });

    expect(
      (await DatabaseService.instance.getUpcomingAppointments()).map(
        (item) => item.id,
      ),
      contains(id),
    );

    await DatabaseService.instance.setAppointmentStatus(
      id,
      AppointmentStatus.noShow,
    );

    final restored = await DatabaseService.instance.getAppointmentById(id);
    expect(restored!.status, AppointmentStatus.noShow);
    expect(restored.isCompleted, isFalse);
    expect(
      (await DatabaseService.instance.getUpcomingAppointments()).map(
        (item) => item.id,
      ),
      isNot(contains(id)),
    );
  });
}

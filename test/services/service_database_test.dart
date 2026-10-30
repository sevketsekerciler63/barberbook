import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/barber_service.dart';
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
    'edited service persists and archived service is excluded from new choices',
    () async {
      final id = await DatabaseService.instance.insertService(
        BarberService(
          name: 'Saç + Sakal',
          durationMinutes: 45,
          priceCents: 65000,
        ),
      );
      await DatabaseService.instance.updateService(
        BarberService(
          id: id,
          name: 'Saç + Sakal Premium',
          durationMinutes: 60,
          priceCents: 80000,
          isActive: false,
        ),
      );

      final all = await DatabaseService.instance.getServices(activeOnly: false);
      final active = await DatabaseService.instance.getServices();

      expect(
        all.where((service) => service.id == id).single.name,
        'Saç + Sakal Premium',
      );
      expect(
        all.where((service) => service.id == id).single.durationMinutes,
        60,
      );
      expect(active.where((service) => service.id == id), isEmpty);
    },
  );

  test('archived service remains on saved appointment snapshot', () async {
    final id = await DatabaseService.instance.insertService(
      BarberService(name: 'Eski Paket', durationMinutes: 50),
    );
    final appointmentId = await DatabaseService.instance.insertAppointment(
      Appointment(
        customerName: 'Geçmiş Müşteri',
        appointmentDate: DateTime(2026, 9, 27),
        appointmentTime: '15:00',
        serviceId: id,
        serviceName: 'Eski Paket',
        durationMinutes: 50,
      ),
    );
    await DatabaseService.instance.updateService(
      BarberService(
        id: id,
        name: 'Eski Paket',
        durationMinutes: 50,
        isActive: false,
      ),
    );

    final appointment = await DatabaseService.instance.getAppointmentById(
      appointmentId,
    );
    expect(appointment!.serviceName, 'Eski Paket');
    expect(appointment.serviceId, id);
  });
}

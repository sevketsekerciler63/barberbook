import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/hairstyle_template.dart';
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
    'custom hairstyle template persists and can be attached to appointment',
    () async {
      final id = await DatabaseService.instance.insertHairstyleTemplate(
        HairstyleTemplate(name: 'Ustanın özel taper modeli'),
      );

      final templates = await DatabaseService.instance.getHairstyleTemplates();
      expect(templates.single.id, id);
      expect(templates.single.appointmentHairstyleId, 'custom:$id');

      final appointmentId = await DatabaseService.instance.insertAppointment(
        Appointment(
          customerName: 'Özel Model Müşterisi',
          appointmentDate: DateTime(2026, 9, 27),
          appointmentTime: '11:00',
          hairstyleId: templates.single.appointmentHairstyleId,
          hairstyleName: templates.single.name,
        ),
      );
      final saved = await DatabaseService.instance.getAppointmentById(
        appointmentId,
      );

      expect(saved!.hairstyleId, 'custom:$id');
      expect(saved.hairstyleName, 'Ustanın özel taper modeli');
    },
  );
}

import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/customer_phone_service.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);

  test(
    'refresh reflects edited and cleared numbers without retaining old values',
    () async {
      final db = DatabaseService.instance;
      final id = await db.insertCustomer(
        Customer(name: 'Same name', phone: '05000000001'),
      );
      final secondId = await db.insertCustomer(
        Customer(name: 'Same name', phone: '05000000002'),
      );
      final appointments = [
        for (final customerId in [id, id, secondId])
          Appointment(
            customerId: customerId,
            customerName: 'Same name',
            appointmentDate: DateTime.now(),
            appointmentTime: '12:00',
          ),
      ];
      expect(await CustomerPhoneService.load(appointments), {
        id: '05000000001',
        secondId: '05000000002',
      });
      await db.updateCustomer(
        (await db.getCustomerById(id))!.copyWith(phone: '05000000003'),
      );
      expect(
        (await CustomerPhoneService.load(appointments))[id],
        '05000000003',
      );
      await db.updateCustomer(
        (await db.getCustomerById(id))!.copyWith(phone: ''),
      );
      expect(await CustomerPhoneService.load(appointments), {
        secondId: '05000000002',
      });
      expect(await CustomerPhoneService.load([]), isEmpty);
    },
  );
}

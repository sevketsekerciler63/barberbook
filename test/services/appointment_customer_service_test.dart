import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/appointment_customer_service.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  final db = DatabaseService.instance;
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);

  test(
    'typing the same name creates a distinct customer without overwriting',
    () async {
      final firstId = await db.insertCustomer(
        Customer(
          name: 'Ahmet Yılmaz',
          phone: '05000000001',
          notes: 'Eski müşteri',
        ),
      );
      final resolved = await AppointmentCustomerService.resolve(
        name: ' Ahmet Yılmaz ',
        phone: '05000000002',
      );
      expect(resolved.id, isNot(firstId));
      expect(resolved.name, 'Ahmet Yılmaz');
      expect((await db.getCustomerById(firstId))!.phone, '05000000001');
      expect((await db.getAllCustomers()).length, 2);
    },
  );

  test(
    'selected customer phone update preserves photo and other metadata',
    () async {
      final createdAt = DateTime(2025, 1, 2);
      final id = await db.insertCustomer(
        Customer(
          name: 'Seçilen Müşteri',
          phone: '05000000001',
          notes: 'Kalıcı not',
          photoPath: '/photos/reference.jpg',
          favoriteHairstyle: 'Taper',
          totalAppointments: 7,
          lastAppointmentDate: DateTime(2026, 1, 1),
          createdAt: createdAt,
        ),
      );
      await AppointmentCustomerService.resolve(
        selectedCustomerId: id,
        name: 'Başka ad',
        phone: ' 05000000002 ',
      );
      final updated = (await db.getCustomerById(id))!;
      expect(updated.photoPath, '/photos/reference.jpg');
      expect(updated.name, 'Seçilen Müşteri');
      expect(updated.phone, '05000000002');
      expect(updated.notes, 'Kalıcı not');
      expect(updated.favoriteHairstyle, 'Taper');
      expect(updated.totalAppointments, 7);
      expect(updated.lastAppointmentDate, DateTime(2026, 1, 1));
      expect(updated.createdAt, createdAt);
    },
  );

  test('blank phone keeps selected customer phone', () async {
    final id = await db.insertCustomer(
      Customer(name: 'Müşteri', phone: '05000000001'),
    );
    final customer = await AppointmentCustomerService.resolve(
      selectedCustomerId: id,
      name: 'Müşteri',
      phone: ' ',
    );
    expect(customer.phone, '05000000001');
  });

  test(
    'deleted selection is rejected instead of recreating a customer',
    () async {
      await expectLater(
        AppointmentCustomerService.resolve(
          selectedCustomerId: 999,
          name: 'Eski kayıt',
          phone: '',
        ),
        throwsStateError,
      );
      expect(await db.getAllCustomers(), isEmpty);
    },
  );
}

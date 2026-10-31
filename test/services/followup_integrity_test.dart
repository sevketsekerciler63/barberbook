import 'dart:io';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/services/backup_service.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  final service = DatabaseService.instance;
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);
  Future<int> insert({int? customerId}) => service.insertAppointment(
    Appointment(
      customerId: customerId,
      customerName: 'Deneme',
      appointmentDate: DateTime(2026, 11, 1),
      appointmentTime: '10:00',
    ),
  );

  test(
    'collected money cannot be rewritten as credit or another paid amount',
    () async {
      final id = await insert();
      await service.completeAppointmentWithPayment(
        id,
        Payment(
          appointmentId: id,
          amountCents: 50000,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          paidAt: DateTime(2026, 10, 31, 12),
        ),
      );
      await service.setAppointmentStatus(id, AppointmentStatus.planned);
      for (final status in [PaymentStatus.pending, PaymentStatus.paid]) {
        await expectLater(
          service.completeAppointmentWithPayment(
            id,
            Payment(
              appointmentId: id,
              amountCents: 40000,
              status: status,
              method: status == PaymentStatus.pending
                  ? PaymentMethod.credit
                  : PaymentMethod.card,
            ),
          ),
          throwsStateError,
        );
      }
      await service.completeAppointmentWithoutPayment(id);
      final payment = (await service.getPaymentForAppointment(id))!;
      expect(payment.status, PaymentStatus.paid);
      expect(payment.amountCents, 50000);
      expect(
        (await service.getCashReport(
          DateTime(2026, 10, 31),
          DateTime(2026, 10, 31),
        )).collectedCents,
        50000,
      );
      expect(await service.getOpenReceivables(), isEmpty);
    },
  );
  test(
    'appointment insert rolls back when customer stats update fails',
    () async {
      final id = await service.insertCustomer(Customer(name: 'Müşteri'));
      final db = await service.database;
      await db.execute(
        "CREATE TRIGGER fail_stats BEFORE UPDATE OF totalAppointments ON customers BEGIN SELECT RAISE(ABORT, 'simulated failure'); END",
      );
      await expectLater(
        insert(customerId: id),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('appointments'), isEmpty);
    },
  );
  test('backup cannot report success for a missing referenced photo', () async {
    await service.insertCustomer(
      Customer(
        name: 'Fotoğraflı',
        photoPath: p.join(
          p.dirname(isolation.databasePath),
          'photos',
          'missing.jpg',
        ),
      ),
    );
    await expectLater(BackupService.instance.createBackup(), throwsStateError);
    expect(await BackupService.instance.listBackups(), isEmpty);
  });
  test(
    'backup with 999 existing photos passes the same validation used to restore',
    () async {
      final id = await service.insertCustomer(Customer(name: 'Fotoğraflı'));
      final photos = Directory(
        p.join(p.dirname(isolation.databasePath), 'photos'),
      );
      await photos.create();
      final db = await service.database;
      final batch = db.batch();
      for (var i = 0; i < 999; i++) {
        final file = File(p.join(photos.path, 'photo_$i.jpg'));
        await file.writeAsBytes([i % 256]);
        batch.insert('customer_photos', {
          'customerId': id,
          'photoPath': file.path,
          'type': 'reference',
          'source': 'gallery',
          'createdAt': DateTime(2026, 10, 31).toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
      final backup = await BackupService.instance.createBackup();
      await expectLater(
        BackupService.instance.validateBackup(backup),
        completes,
      );
    },
  );

  test(
    'explicit missing-photo backup repairs only the exported snapshot',
    () async {
      final root = p.dirname(isolation.databasePath);
      final missing = p.join(root, 'photos', 'missing.jpg');
      final id = await service.insertCustomer(
        Customer(name: 'Korunacak', phone: '05000000001', photoPath: missing),
      );
      final db = await service.database;
      await db.insert('customer_photos', {
        'customerId': id,
        'photoPath': missing,
        'type': 'reference',
        'source': 'gallery',
        'createdAt': DateTime.now().toIso8601String(),
      });
      final backup = await BackupService.instance.createBackup(
        omitMissingPhotos: true,
      );
      await expectLater(
        BackupService.instance.validateBackup(backup),
        completes,
      );
      expect((await service.getCustomerById(id))!.photoPath, missing);
      expect(await service.getCustomerPhotos(id), hasLength(1));
      await expectLater(
        BackupService.instance.restoreBackup(backup),
        throwsA(isA<MissingBackupPhotosException>()),
      );
      await BackupService.instance.restoreBackup(
        backup,
        omitMissingSafetyPhotos: true,
      );
      expect((await service.getCustomerById(id))!.photoPath, isNull);
      expect((await service.getCustomerById(id))!.phone, '05000000001');
      expect(await service.getCustomerPhotos(id), isEmpty);
    },
  );

  test(
    'whole form rolls back a new customer and phone edits when appointment write fails',
    () async {
      final db = await service.database;
      await db.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON appointments BEGIN SELECT RAISE(ABORT, 'simulated appointment failure'); END",
      );
      final appointment = Appointment(
        customerName: 'Yeni',
        appointmentDate: DateTime(2026, 11, 1),
        appointmentTime: '11:00',
      );
      await expectLater(
        service.saveAppointmentForCustomer(
          appointment: appointment,
          phone: '05000000001',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await service.getAllCustomers(), isEmpty);
      final id = await service.insertCustomer(
        Customer(name: 'Eski', phone: '05000000002', notes: 'Korunacak'),
      );
      await expectLater(
        service.saveAppointmentForCustomer(
          appointment: appointment,
          selectedCustomerId: id,
          phone: '05000000003',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect((await service.getCustomerById(id))!.phone, '05000000002');
      expect((await service.getCustomerById(id))!.notes, 'Korunacak');
      expect(await db.query('appointments'), isEmpty);
    },
  );

  test(
    'form uses selected identity even before a display customer has loaded',
    () async {
      final id = await service.insertCustomer(
        Customer(name: 'Güncel ad', phone: '05000000001'),
      );
      final saved = await service.saveAppointmentForCustomer(
        appointment: Appointment(
          customerName: 'Eski ekrandaki ad',
          appointmentDate: DateTime(2026, 11, 1),
          appointmentTime: '11:00',
        ),
        selectedCustomerId: id,
        phone: '',
      );
      expect(saved.customerId, id);
      expect(saved.customerName, 'Güncel ad');
      expect(await service.getAllCustomers(), hasLength(1));
      expect((await service.getCustomerById(id))!.phone, '05000000001');
    },
  );

  test('write-time capacity recheck cannot leave an extra customer', () async {
    await insert();
    await expectLater(
      service.saveAppointmentForCustomer(
        appointment: Appointment(
          customerName: 'Yeni',
          appointmentDate: DateTime(2026, 11, 1),
          appointmentTime: '10:00',
        ),
        phone: '',
      ),
      throwsStateError,
    );
    expect(await service.getAllCustomers(), isEmpty);
  });
  test(
    'equivalent midnight formats are included in cash and collection date ranges',
    () async {
      final first = await insert();
      final second = await insert();
      final db = await service.database;
      await db.insert('payments', {
        'appointmentId': first,
        'amountCents': 50000,
        'status': 'paid',
        'method': 'cash',
        'paidAt': '2026-10-31T00:00:00',
        'createdAt': '2026-10-31T00:00:00',
      });
      await db.insert('payments', {
        'appointmentId': second,
        'amountCents': 30000,
        'status': 'pending',
        'method': 'credit',
        'createdAt': '2026-10-31T00:00:00',
      });
      await db.insert('payment_transactions', {
        'appointmentId': second,
        'type': 'collection',
        'amountCents': 10000,
        'method': 'cash',
        'occurredAt': '2026-10-31T00:00:00',
        'createdAt': '2026-10-31T00:00:00',
      });
      expect(
        await service.getPaymentsForDate(DateTime(2026, 10, 31)),
        hasLength(1),
      );
      expect(
        await service.getPaymentTransactionsForDate(DateTime(2026, 10, 31)),
        hasLength(1),
      );
      expect(
        (await service.getCashReport(
          DateTime(2026, 10, 31),
          DateTime(2026, 10, 31),
        )).collectedCents,
        60000,
      );
    },
  );

  test(
    'profile and photo history are atomic for both new and edited customers',
    () async {
      final db = await service.database;
      await db.execute(
        "CREATE TRIGGER fail_photo BEFORE INSERT ON customer_photos BEGIN SELECT RAISE(ABORT, 'simulated photo failure'); END",
      );
      await expectLater(
        service.saveCustomerWithPhoto(
          Customer(name: 'Yeni'),
          newPhotoPath: '/synthetic/photo.jpg',
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await service.getAllCustomers(), isEmpty);
      final id = await service.insertCustomer(
        Customer(name: 'Eski', phone: '05000000001'),
      );
      await expectLater(
        service.saveCustomerWithPhoto(
          Customer(id: id, name: 'Yeni ad', phone: '05000000002'),
          newPhotoPath: '/synthetic/photo.jpg',
        ),
        throwsA(isA<DatabaseException>()),
      );
      final customer = (await service.getCustomerById(id))!;
      expect(customer.name, 'Eski');
      expect(customer.phone, '05000000001');
      expect(await service.getCustomerPhotos(id), isEmpty);
    },
  );
}

import 'dart:io';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/alarm_reconciliation.dart';
import 'package:berber_randevu/services/backup_service.dart';
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
    'alarm synchronization reads restored data and replaces the old device set',
    () async {
      final date = DateTime.now().add(const Duration(days: 1));
      final originalId = await db.insertAppointment(
        Appointment(
          customerName: 'Yedekteki',
          appointmentDate: date,
          appointmentTime: '10:00',
        ),
      );
      final backup = await BackupService.instance.createBackup();
      await db.deleteAppointment(originalId);
      final liveId = await db.insertAppointment(
        Appointment(
          customerName: 'Eski alarm',
          appointmentDate: date,
          appointmentTime: '11:00',
        ),
      );
      final device = <int>{liveId};
      final result = await BackupService.instance.restoreBackup(
        backup,
        synchronizeAlarms: () async {
          final restored = await db.getUpcomingAppointments();
          expect(restored.single.customerName, 'Yedekteki');
          await rebuildAppointmentAlarms(
            appointments: restored,
            now: DateTime.now(),
            cancelAll: () async => device.clear(),
            schedule: (a) async {
              device.add(a.id!);
              return true;
            },
          );
        },
      );
      expect(result.alarmsSynchronized, isTrue);
      expect(device, {originalId});
    },
  );

  test(
    'OS alarm failure warns without rolling back the successfully restored backup',
    () async {
      await db.insertCustomer(Customer(name: 'Yedekteki'));
      final backup = await BackupService.instance.createBackup();
      await db.insertCustomer(Customer(name: 'Sonradan eklenen'));
      final result = await BackupService.instance.restoreBackup(
        backup,
        synchronizeAlarms: () async =>
            throw StateError('native permission failure'),
      );
      expect(result.alarmsSynchronized, isFalse);
      expect((await db.getAllCustomers()).map((c) => c.name), ['Yedekteki']);
    },
  );

  test('invalid backup never changes alarms or existing data', () async {
    await db.insertCustomer(Customer(name: 'Mevcut'));
    final invalid = File('${isolation.databasePath}.invalid');
    await invalid.writeAsString('invalid backup');
    var synchronized = false;
    await expectLater(
      BackupService.instance.restoreBackup(
        invalid,
        synchronizeAlarms: () async {
          synchronized = true;
        },
      ),
      throwsStateError,
    );
    expect(synchronized, isFalse);
    expect((await db.getAllCustomers()).single.name, 'Mevcut');
  });
}

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
    'v7 database upgrades to v12 with payment records enabled by default',
    () async {
      final legacyDatabase = await openDatabase(
        isolation.databasePath,
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT,
            notes TEXT,
            favoriteHairstyle TEXT,
            totalAppointments INTEGER DEFAULT 0,
            lastAppointmentDate TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE appointments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerId INTEGER,
            customerName TEXT NOT NULL,
            appointmentDate TEXT NOT NULL,
            appointmentTime TEXT NOT NULL,
            hairstyleId TEXT,
            hairstyleName TEXT,
            serviceId INTEGER,
            serviceName TEXT,
            durationMinutes INTEGER NOT NULL DEFAULT 30,
            priceCents INTEGER,
            notes TEXT,
            isCompleted INTEGER DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'planned',
            createdAt TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE services (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            durationMinutes INTEGER NOT NULL,
            priceCents INTEGER,
            isActive INTEGER NOT NULL DEFAULT 1
          )
        ''');
          await db.execute('''
          CREATE TABLE working_hours (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            weekday INTEGER NOT NULL,
            startMinute INTEGER NOT NULL,
            endMinute INTEGER NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE closed_time_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            startAt TEXT NOT NULL,
            endAt TEXT NOT NULL,
            reason TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            appointmentId INTEGER NOT NULL UNIQUE,
            amountCents INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'unknown',
            method TEXT NOT NULL DEFAULT 'other',
            discountCents INTEGER NOT NULL DEFAULT 0,
            tipCents INTEGER NOT NULL DEFAULT 0,
            paidAt TEXT,
            note TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
          await db.execute('''
          CREATE TABLE payment_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            appointmentId INTEGER NOT NULL,
            type TEXT NOT NULL,
            amountCents INTEGER NOT NULL,
            method TEXT NOT NULL,
            occurredAt TEXT NOT NULL,
            note TEXT,
            createdAt TEXT NOT NULL
          )
        ''');
        },
      );

      await legacyDatabase.insert('customers', {
        'id': 7,
        'name': 'Migration Müşterisi',
        'phone': '05000000000',
        'createdAt': '2026-09-20T12:00:00.000',
      });
      await legacyDatabase.insert('appointments', {
        'id': 11,
        'customerId': 7,
        'customerName': 'Migration Müşterisi',
        'appointmentDate': '2026-09-21',
        'appointmentTime': '14:30',
        'serviceName': 'Saç Kesimi',
        'durationMinutes': 30,
        'isCompleted': 0,
        'status': 'planned',
        'createdAt': '2026-09-20T12:00:00.000',
      });
      await legacyDatabase.close();

      final upgradedDatabase = await DatabaseService.instance.database;

      expect(await upgradedDatabase.getVersion(), 12);
      expect(
        await _tableNames(upgradedDatabase),
        containsAll(<String>[
          'working_hours',
          'closed_time_blocks',
          'payments',
          'payment_transactions',
          'customer_photos',
          'hairstyle_templates',
          'shop_settings',
        ]),
      );

      final customers = await upgradedDatabase.query(
        'customers',
        where: 'id = 7',
      );
      final appointments = await upgradedDatabase.query(
        'appointments',
        where: 'id = 11',
      );

      expect(customers.single['name'], 'Migration Müşterisi');
      expect(customers.single['photoPath'], isNull);
      expect(await upgradedDatabase.query('customer_photos'), isEmpty);
      expect(appointments.single['status'], 'planned');
      expect(appointments.single['serviceName'], 'Saç Kesimi');
      expect(appointments.single['durationMinutes'], 30);
      expect(
        (await upgradedDatabase.query(
          'shop_settings',
        )).single['appointmentCapacity'],
        1,
      );
      expect(
        (await upgradedDatabase.query(
          'shop_settings',
        )).single['paymentEnabled'],
        1,
      );
    },
  );

  test(
    'v11 shop settings keep appointment capacity when payment is added',
    () async {
      final legacyDatabase = await openDatabase(
        isolation.databasePath,
        version: 11,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE shop_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            appointmentCapacity INTEGER NOT NULL DEFAULT 1
              CHECK (appointmentCapacity >= 1)
          )
        ''');
        },
      );
      await legacyDatabase.insert('shop_settings', {
        'id': 1,
        'appointmentCapacity': 3,
      });
      await legacyDatabase.close();

      final upgradedDatabase = await DatabaseService.instance.database;
      final settings = (await upgradedDatabase.query('shop_settings')).single;

      expect(await upgradedDatabase.getVersion(), 12);
      expect(settings['appointmentCapacity'], 3);
      expect(settings['paymentEnabled'], 1);
    },
  );
}

Future<List<String>> _tableNames(Database database) async {
  final rows = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((row) => row['name']! as String).toList();
}

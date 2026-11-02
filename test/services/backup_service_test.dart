import 'dart:io';

import 'package:archive/archive.dart';
import 'package:berber_randevu/services/backup_service.dart';
import 'package:berber_randevu/services/customer_photo_storage.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String databasePath;
  late Directory scratch;

  setUp(() async {
    await DatabaseService.instance.closeDatabase();
    scratch = await Directory.systemTemp.createTemp('barber_backup_test_');
    await databaseFactory.setDatabasesPath(scratch.path);
    databasePath = p.join(scratch.path, 'barberbook.db');
    await deleteDatabase(databasePath);
  });

  tearDown(() async {
    await DatabaseService.instance.closeDatabase();
    await deleteDatabase(databasePath);
    if (await scratch.exists()) await scratch.delete(recursive: true);
  });

  test(
    'invalid non-empty backup is rejected without changing active data',
    () async {
      final db = await DatabaseService.instance.database;
      await db.insert('customers', {
        'name': 'Korunacak Müşteri',
        'createdAt': DateTime(2026, 9, 21).toIso8601String(),
      });
      final invalid = File(p.join(scratch.path, 'invalid.db'));
      await invalid.writeAsString('sqlite olmayan içerik');

      await expectLater(
        BackupService.instance.restoreBackup(invalid),
        throwsA(isA<StateError>()),
      );

      final reopened = await DatabaseService.instance.database;
      final customers = await reopened.query('customers');
      expect(customers.single['name'], 'Korunacak Müşteri');
    },
  );

  test('valid v12 application backup passes validation', () async {
    final db = await DatabaseService.instance.database;
    expect(await db.getVersion(), 13);
    final backup = await BackupService.instance.createBackup();
    await expectLater(BackupService.instance.validateBackup(backup), completes);
  });

  test(
    'new archive backup stores managed photos and restores valid photo paths',
    () async {
      final fixture = File(p.join(scratch.path, 'fixture.jpg'));
      final photoBytes = <int>[0xff, 0xd8, 0xff, 0x00, 0x42];
      await fixture.writeAsBytes(photoBytes);
      final managedPhotoPath = await CustomerPhotoStorage.importImage(
        fixture.path,
      );
      final db = await DatabaseService.instance.database;
      final customerId = await db.insert('customers', {
        'name': 'Fotoğraflı Müşteri',
        'photoPath': managedPhotoPath,
        'createdAt': DateTime(2026, 9, 21).toIso8601String(),
      });
      await db.insert('customer_photos', {
        'customerId': customerId,
        'photoPath': managedPhotoPath,
        'type': 'reference',
        'source': 'gallery',
        'createdAt': DateTime(2026, 9, 21).toIso8601String(),
      });

      final backup = await BackupService.instance.createBackup();

      expect(p.extension(backup.path), '.zip');
      final archive = ZipDecoder().decodeBytes(await backup.readAsBytes());
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, containsAll({'manifest.json', 'database/barberbook.db'}));
      expect(names.where((name) => name.startsWith('photos/')), hasLength(1));

      await DatabaseService.instance.closeDatabase();
      await File(managedPhotoPath).delete();
      final restoredDeviceDirectory = Directory(
        p.join(scratch.path, 'restored_device'),
      );
      await restoredDeviceDirectory.create();
      await databaseFactory.setDatabasesPath(restoredDeviceDirectory.path);
      await BackupService.instance.restoreBackup(backup);

      final restored = await DatabaseService.instance.database;
      final customers = await restored.query('customers');
      final restoredPhotoPath = customers.single['photoPath'] as String;
      final photoHistory = await restored.query(
        'customer_photos',
        where: 'customerId = ?',
        whereArgs: [customers.single['id']],
      );
      expect(await File(restoredPhotoPath).readAsBytes(), photoBytes);
      expect(photoHistory.single['photoPath'], restoredPhotoPath);
      expect(
        p.dirname(restoredPhotoPath),
        p.join(await getDatabasesPath(), 'photos'),
      );
    },
  );

  test('legacy db backup validates and restores without photos', () async {
    final db = await DatabaseService.instance.database;
    await db.insert('customers', {
      'name': 'Eski Yedek Müşterisi',
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    await DatabaseService.instance.closeDatabase();
    final legacyBackup = File(p.join(scratch.path, 'legacy.db'));
    await File(databasePath).copy(legacyBackup.path);

    final active = await DatabaseService.instance.database;
    await active.insert('customers', {
      'name': 'Sonraki Müşteri',
      'createdAt': DateTime(2026, 9, 22).toIso8601String(),
    });

    await expectLater(
      BackupService.instance.validateBackup(legacyBackup),
      completes,
    );
    await BackupService.instance.restoreBackup(legacyBackup);

    final restored = await DatabaseService.instance.database;
    final customers = await restored.query('customers', orderBy: 'id');
    expect(customers.map((customer) => customer['name']), [
      'Eski Yedek Müşterisi',
    ]);
    expect(customers.single['photoPath'], isNull);
  });

  test('invalid archive is rejected without changing active data', () async {
    final db = await DatabaseService.instance.database;
    await db.insert('customers', {
      'name': 'Arşivden Korunacak Müşteri',
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    final invalid = File(p.join(scratch.path, 'invalid.zip'));
    await invalid.writeAsString('zip olmayan içerik');

    await expectLater(
      BackupService.instance.restoreBackup(invalid),
      throwsA(isA<StateError>()),
    );

    final reopened = await DatabaseService.instance.database;
    final customers = await reopened.query('customers');
    expect(customers.single['name'], 'Arşivden Korunacak Müşteri');
  });

  test('backup preview reports schema and record counts', () async {
    final db = await DatabaseService.instance.database;
    await db.insert('customers', {
      'name': 'Önizleme Müşterisi',
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    await db.insert('appointments', {
      'customerName': 'Önizleme Müşterisi',
      'appointmentDate': DateTime(2026, 9, 21).toIso8601String(),
      'appointmentTime': '14:00',
      'durationMinutes': 30,
      'status': 'planned',
      'isCompleted': 0,
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    final backup = await BackupService.instance.createBackup();

    final preview = await BackupService.instance.previewBackup(backup);

    expect(preview.schemaVersion, 13);
    expect(preview.customerCount, 1);
    expect(preview.appointmentCount, 1);
    expect(preview.serviceCount, 3);
    expect(preview.paymentCount, 0);
    expect(preview.transactionCount, 0);
  });

  test('v12 backup missing current schema tables is rejected', () async {
    final invalidPath = p.join(scratch.path, 'incomplete_v12.db');
    final invalid = await openDatabase(
      invalidPath,
      version: 12,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY)');
        await db.execute('CREATE TABLE appointments (id INTEGER PRIMARY KEY)');
        await db.execute('CREATE TABLE payments (id INTEGER PRIMARY KEY)');
        await db.execute(
          'CREATE TABLE payment_transactions (id INTEGER PRIMARY KEY)',
        );
      },
    );
    await invalid.close();

    await expectLater(
      BackupService.instance.validateBackup(File(invalidPath)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      BackupService.instance.restoreBackup(File(invalidPath)),
      throwsA(isA<StateError>()),
    );
  });

  test('legacy db restore clears unmanaged photo references', () async {
    final fixture = File(p.join(scratch.path, 'legacy_fixture.jpg'));
    await fixture.writeAsBytes(<int>[0xff, 0xd8, 0xff, 0x00, 0x42]);
    final oldPhotoPath = await CustomerPhotoStorage.importImage(fixture.path);
    final db = await DatabaseService.instance.database;
    final customerId = await db.insert('customers', {
      'name': 'Eski Fotoğraflı Müşteri',
      'photoPath': oldPhotoPath,
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    await db.insert('customer_photos', {
      'customerId': customerId,
      'photoPath': oldPhotoPath,
      'type': 'reference',
      'source': 'gallery',
      'createdAt': DateTime(2026, 9, 21).toIso8601String(),
    });
    await DatabaseService.instance.closeDatabase();

    final legacyBackup = File(p.join(scratch.path, 'legacy_with_photos.db'));
    await File(databasePath).copy(legacyBackup.path);

    final restoredDeviceDirectory = Directory(
      p.join(scratch.path, 'legacy_restored_device'),
    );
    await restoredDeviceDirectory.create();
    await databaseFactory.setDatabasesPath(restoredDeviceDirectory.path);
    final stalePhotosDirectory = Directory(
      p.join(restoredDeviceDirectory.path, 'photos'),
    );
    await stalePhotosDirectory.create();
    await File(
      p.join(stalePhotosDirectory.path, 'stale.jpg'),
    ).writeAsBytes(<int>[1, 2, 3]);

    await BackupService.instance.restoreBackup(legacyBackup);

    final restored = await DatabaseService.instance.database;
    final customers = await restored.query('customers');
    expect(customers.single['photoPath'], isNull);
    expect(await restored.query('customer_photos'), isEmpty);
    // The replacement may retain an empty managed directory, never stale files.
    expect(
      await File(p.join(stalePhotosDirectory.path, 'stale.jpg')).exists(),
      isFalse,
    );
    expect(await stalePhotosDirectory.list().toList(), isEmpty);
  });

  test('v7 backup missing transaction table is rejected', () async {
    final invalidPath = p.join(scratch.path, 'missing_transactions.db');
    final invalid = await openDatabase(
      invalidPath,
      version: 7,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY)');
        await db.execute('CREATE TABLE appointments (id INTEGER PRIMARY KEY)');
        await db.execute('CREATE TABLE payments (id INTEGER PRIMARY KEY)');
      },
    );
    await invalid.close();

    await expectLater(
      BackupService.instance.validateBackup(File(invalidPath)),
      throwsA(isA<StateError>()),
    );
  });
}

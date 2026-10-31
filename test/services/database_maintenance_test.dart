import 'dart:async';
import 'dart:io';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:berber_randevu/services/restore_file_transaction.dart';
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
  test(
    'normal writes wait for maintenance and resume on the retained connection',
    () async {
      await service.insertCustomer(Customer(name: 'Before'));
      final entered = Completer<void>();
      final release = Completer<void>();
      final maintenance = service.withMaintenance((access) async {
        entered.complete();
        await release.future;
        await access.open();
      });
      await entered.future;
      var finished = false;
      final write = service
          .insertCustomer(Customer(name: 'After'))
          .then((_) => finished = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(finished, isFalse);
      release.complete();
      await maintenance;
      await write;
      expect(
        (await service.getAllCustomers()).map((c) => c.name),
        containsAll(['Before', 'After']),
      );
    },
  );
  test(
    'queued maintenance operations do not release normal reads between swaps',
    () async {
      await service.database;
      final firstEntered = Completer<void>();
      final firstRelease = Completer<void>();
      final secondEntered = Completer<void>();
      final secondRelease = Completer<void>();
      final first = service.withMaintenance((_) async {
        firstEntered.complete();
        await firstRelease.future;
      });
      await firstEntered.future;
      final second = service.withMaintenance((_) async {
        secondEntered.complete();
        await secondRelease.future;
      });
      var read = false;
      final pending = service.database.then((_) => read = true);
      firstRelease.complete();
      await first;
      await secondEntered.future;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(read, isFalse);
      secondRelease.complete();
      await second;
      await pending;
      expect(read, isTrue);
    },
  );
  test(
    'maintenance failure releases the gate and invalidates its scoped access',
    () async {
      await service.insertCustomer(Customer(name: 'Retained'));
      late DatabaseMaintenance access;
      await expectLater(
        service.withMaintenance((session) async {
          access = session;
          throw StateError('simulated failure');
        }),
        throwsStateError,
      );
      expect((await service.getAllCustomers()).single.name, 'Retained');
      expect(() => access.open(), throwsStateError);
    },
  );
  test(
    'DatabaseService startup recovers an interrupted swap before opening SQLite',
    () async {
      await service.insertCustomer(Customer(name: 'Original'));
      await service.closeDatabase();
      final root = p.dirname(isolation.databasePath);
      final candidate = await File(
        isolation.databasePath,
      ).copy(p.join(root, 'candidate.db'));
      final incoming = await openDatabase(
        candidate.path,
        singleInstance: false,
      );
      await incoming.insert(
        'customers',
        Customer(name: 'Replacement only').toMap()..remove('id'),
      );
      await incoming.close();
      final photos = Directory(p.join(root, 'candidate_photos'));
      await photos.create();
      final transaction = await RestoreFileTransaction.at(root);
      await expectLater(
        transaction.install(
          database: candidate,
          photos: photos,
          afterStep: (step) async {
            if (step == RestoreSwapStep.newDatabaseInstalled) {
              throw StateError('simulated process exit');
            }
          },
        ),
        throwsStateError,
      );
      transaction.release();
      expect((await service.getAllCustomers()).map((c) => c.name), [
        'Original',
      ]);
      expect(
        await Directory(p.join(root, 'restore_transaction')).exists(),
        isFalse,
      );
    },
  );
}

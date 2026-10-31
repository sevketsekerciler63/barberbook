import 'dart:io';
import 'package:berber_randevu/services/restore_file_transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory scratch;
  late Directory live;
  late File incoming;
  late Directory photos;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('barber_restore_swap_');
    live = Directory(p.join(scratch.path, 'live'));
    await live.create();
    await File(
      p.join(live.path, 'barberbook.db'),
    ).writeAsString('old database');
    final old = Directory(p.join(live.path, 'photos'));
    await old.create();
    await File(p.join(old.path, 'old.jpg')).writeAsString('old photo');
    incoming = File(p.join(scratch.path, 'incoming.db'));
    await incoming.writeAsString('new database');
    photos = Directory(p.join(scratch.path, 'incoming_photos'));
    await photos.create();
    await File(p.join(photos.path, 'new.jpg')).writeAsString('new photo');
  });
  tearDown(() async {
    final resolved = await scratch.resolveSymbolicLinks();
    if (!p.isWithin(
      await Directory.systemTemp.resolveSymbolicLinks(),
      resolved,
    )) {
      throw StateError('Unsafe test cleanup');
    }
    await scratch.delete(recursive: true);
  });
  for (final step in RestoreSwapStep.values) {
    test(
      'startup recovers both old DB and photos after interruption at ${step.name}',
      () async {
        final transaction = await RestoreFileTransaction.at(live.path);
        await expectLater(
          transaction.install(
            database: incoming,
            photos: photos,
            afterStep: (current) async {
              if (current == step) throw StateError('simulated process exit');
            },
          ),
          throwsStateError,
        );
        transaction.release();
        await RestoreFileTransaction.recoverBeforeOpening(live.path);
        expect(
          await File(p.join(live.path, 'barberbook.db')).readAsString(),
          'old database',
        );
        expect(
          await File(p.join(live.path, 'photos', 'old.jpg')).readAsString(),
          'old photo',
        );
        expect(
          await File(p.join(live.path, 'photos', 'new.jpg')).exists(),
          isFalse,
        );
        await RestoreFileTransaction.recoverBeforeOpening(live.path);
        expect(
          await Directory(p.join(live.path, 'restore_transaction')).exists(),
          isFalse,
        );
      },
    );
  }
  test(
    'committed replacement survives startup without restoring old files',
    () async {
      final transaction = await RestoreFileTransaction.at(live.path);
      await transaction.install(database: incoming, photos: photos);
      // A crash after writing the commit marker but before cleanup.
      await File(
        p.join(live.path, 'restore_transaction', 'committed'),
      ).writeAsString('committed', flush: true);
      transaction.release();
      await RestoreFileTransaction.recoverBeforeOpening(live.path);
      expect(
        await File(p.join(live.path, 'barberbook.db')).readAsString(),
        'new database',
      );
      expect(
        await File(p.join(live.path, 'photos', 'new.jpg')).readAsString(),
        'new photo',
      );
    },
  );
  test(
    'new hot journal cannot contaminate the recovered old database family',
    () async {
      await File(
        p.join(live.path, 'barberbook.db-wal'),
      ).writeAsString('old wal');
      final transaction = await RestoreFileTransaction.at(live.path);
      await transaction.install(database: incoming, photos: photos);
      await File(
        p.join(live.path, 'barberbook.db-wal'),
      ).writeAsString('new wal');
      await File(
        p.join(live.path, 'barberbook.db-journal'),
      ).writeAsString('new hot journal');
      transaction.release();
      await RestoreFileTransaction.recoverBeforeOpening(live.path);
      expect(
        await File(p.join(live.path, 'barberbook.db-wal')).readAsString(),
        'old wal',
      );
      expect(
        await File(p.join(live.path, 'barberbook.db-journal')).exists(),
        isFalse,
      );
    },
  );

  test(
    'interruption during committed cleanup never rolls new data back to the old photo group',
    () async {
      final transaction = await RestoreFileTransaction.at(live.path);
      await transaction.install(database: incoming, photos: photos);
      await expectLater(
        transaction.commit(
          afterRemoved: (name) async {
            if (name == 'old.db') {
              throw StateError('simulated exit during cleanup');
            }
          },
        ),
        throwsStateError,
      );
      transaction.release();
      expect(
        await File(
          p.join(live.path, 'restore_transaction', 'committed'),
        ).exists(),
        isTrue,
      );
      await RestoreFileTransaction.recoverBeforeOpening(live.path);
      expect(
        await File(p.join(live.path, 'barberbook.db')).readAsString(),
        'new database',
      );
      expect(
        await File(p.join(live.path, 'photos', 'new.jpg')).readAsString(),
        'new photo',
      );
      expect(
        await File(p.join(live.path, 'photos', 'old.jpg')).exists(),
        isFalse,
      );
    },
  );
  test('missing original photo directory is restored as absent', () async {
    await Directory(p.join(live.path, 'photos')).delete(recursive: true);
    final transaction = await RestoreFileTransaction.at(live.path);
    await transaction.install(database: incoming, photos: photos);
    transaction.release();
    await RestoreFileTransaction.recoverBeforeOpening(live.path);
    expect(await Directory(p.join(live.path, 'photos')).exists(), isFalse);
  });
  test(
    'corrupt recovery metadata preserves snapshots and refuses silent fresh DB creation',
    () async {
      final transaction = await RestoreFileTransaction.at(live.path);
      await transaction.install(database: incoming, photos: photos);
      transaction.release();
      await File(
        p.join(live.path, 'restore_transaction', 'state.json'),
      ).writeAsString('{broken');
      await expectLater(
        RestoreFileTransaction.recoverBeforeOpening(live.path),
        throwsStateError,
      );
      expect(
        await File(
          p.join(live.path, 'restore_transaction', 'old.db'),
        ).readAsString(),
        'old database',
      );
    },
  );
  test(
    'a live database cannot be accidentally supplied as its own restore candidate',
    () async {
      final transaction = await RestoreFileTransaction.at(live.path);
      await expectLater(
        transaction.install(
          database: File(p.join(live.path, 'barberbook.db')),
          photos: photos,
        ),
        throwsStateError,
      );
      expect(
        await File(p.join(live.path, 'barberbook.db')).readAsString(),
        'old database',
      );
      expect(
        await Directory(p.join(live.path, 'restore_transaction')).exists(),
        isFalse,
      );
    },
  );
}

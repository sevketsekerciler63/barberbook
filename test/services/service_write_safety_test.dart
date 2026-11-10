import 'package:berber_randevu/models/barber_service.dart';
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
    'concurrent normalized active names create exactly one service',
    () async {
      Future<bool> create(String name) async {
        try {
          await db.insertService(
            BarberService(name: name, durationMinutes: 30),
          );
          return true;
        } on StateError {
          return false;
        }
      }

      final results = await Future.wait([
        create('ŞEKİLLENDİRME'),
        create(' sekillendirme '),
      ]);
      expect(results.where((success) => success), hasLength(1));
      final services = await db.getServices(activeOnly: false);
      expect(
        services.where((s) => s.name.toLowerCase().contains('ek')),
        hasLength(1),
      );
    },
  );

  test(
    'archive and rename reject collisions, unchanged legacy duplicates stay editable',
    () async {
      final connection = await db.database;
      final first = await connection.insert(
        'services',
        BarberService(name: 'Özel kesim', durationMinutes: 30).toMap(),
      );
      final duplicate = await connection.insert(
        'services',
        BarberService(name: 'ozel kesim', durationMinutes: 30).toMap(),
      );
      final archived = await db.insertService(
        BarberService(name: 'Özel kesim', durationMinutes: 30, isActive: false),
      );
      await expectLater(
        db.updateService(
          BarberService(id: archived, name: 'Özel kesim', durationMinutes: 30),
        ),
        throwsStateError,
      );
      expect(
        await db.updateService(
          BarberService(id: duplicate, name: 'ozel kesim', durationMinutes: 45),
        ),
        1,
      );
      final other = await db.insertService(
        BarberService(name: 'Başka hizmet', durationMinutes: 20),
      );
      await expectLater(
        db.updateService(
          BarberService(id: other, name: 'Özel kesim', durationMinutes: 30),
        ),
        throwsStateError,
      );
      await db.updateService(
        BarberService(
          id: first,
          name: 'Özel kesim',
          durationMinutes: 30,
          isActive: false,
        ),
      );
      await db.updateService(
        BarberService(
          id: duplicate,
          name: 'ozel kesim',
          durationMinutes: 45,
          isActive: false,
        ),
      );
      expect(
        await db.updateService(
          BarberService(id: archived, name: 'Özel kesim', durationMinutes: 30),
        ),
        1,
      );
    },
  );

  test(
    'service write validates limits and identity without altering legacy reads',
    () async {
      for (final service in [
        BarberService(name: 'a' * 61, durationMinutes: 30),
        BarberService(name: 'Long duration', durationMinutes: 481),
        BarberService(
          name: 'Excessive price',
          durationMinutes: 30,
          priceCents: 1000000000000,
        ),
        BarberService(id: 99, name: 'Injected ID', durationMinutes: 30),
      ]) {
        await expectLater(db.insertService(service), throwsArgumentError);
      }
      await expectLater(
        db.updateService(
          BarberService(id: 999999, name: 'Missing', durationMinutes: 30),
        ),
        throwsStateError,
      );
      final id = await db.insertService(
        BarberService(
          name: ' Valid ',
          durationMinutes: 480,
          priceCents: 999999999999,
        ),
      );
      final saved = (await db.getServices(
        activeOnly: false,
      )).singleWhere((s) => s.id == id);
      expect(saved.name, 'Valid');
      expect(saved.priceCents, 999999999999);
      final raw = await db.database;
      await raw.insert(
        'services',
        BarberService(
          name: 'Legacy long duration',
          durationMinutes: 600,
        ).toMap(),
      );
      expect(
        (await db.getServices(
          activeOnly: false,
        )).any((s) => s.durationMinutes == 600),
        isTrue,
      );
    },
  );
}

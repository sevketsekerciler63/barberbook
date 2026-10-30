import 'dart:io';

import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/models/customer_photo.dart';
import 'package:berber_randevu/services/customer_photo_storage.dart';
import 'package:berber_randevu/services/database_service.dart';
import '../test_helpers/database_test_isolation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final isolation = DatabaseTestIsolation();

  setUp(isolation.setUp);

  tearDown(isolation.tearDown);

  test(
    'customer photos retain history and newest path stays on customer',
    () async {
      final customerId = await DatabaseService.instance.insertCustomer(
        Customer(name: 'Fotoğraf Geçmişi'),
      );

      await DatabaseService.instance.addCustomerPhoto(
        CustomerPhoto(
          customerId: customerId,
          photoPath: '/database/photos/reference.jpg',
          type: CustomerPhotoType.reference,
          source: CustomerPhotoSource.gallery,
        ),
      );
      await DatabaseService.instance.addCustomerPhoto(
        CustomerPhoto(
          customerId: customerId,
          photoPath: '/database/photos/result.jpg',
          type: CustomerPhotoType.result,
          source: CustomerPhotoSource.camera,
        ),
      );

      final customer = await DatabaseService.instance.getCustomerById(
        customerId,
      );
      final photos = await DatabaseService.instance.getCustomerPhotos(
        customerId,
      );

      expect(customer!.photoPath, '/database/photos/result.jpg');
      expect(photos.map((photo) => photo.type), [
        CustomerPhotoType.result,
        CustomerPhotoType.reference,
      ]);
    },
  );

  test('deleting a customer removes managed photo files and history', () async {
    final testDirectory = p.dirname(isolation.databasePath);
    final fixtureA = File(p.join(testDirectory, 'source_a.jpg'));
    final fixtureB = File(p.join(testDirectory, 'source_b.jpg'));
    await fixtureA.writeAsBytes(<int>[1, 2, 3]);
    await fixtureB.writeAsBytes(<int>[4, 5, 6]);
    final photoA = await CustomerPhotoStorage.importImage(fixtureA.path);
    final photoB = await CustomerPhotoStorage.importImage(fixtureB.path);
    final customerId = await DatabaseService.instance.insertCustomer(
      Customer(name: 'Silinecek Fotoğraflı Müşteri'),
    );
    await DatabaseService.instance.addCustomerPhoto(
      CustomerPhoto(
        customerId: customerId,
        photoPath: photoA,
        type: CustomerPhotoType.reference,
        source: CustomerPhotoSource.gallery,
      ),
    );
    await DatabaseService.instance.addCustomerPhoto(
      CustomerPhoto(
        customerId: customerId,
        photoPath: photoB,
        type: CustomerPhotoType.result,
        source: CustomerPhotoSource.camera,
      ),
    );

    await DatabaseService.instance.deleteCustomer(customerId);

    expect(await File(photoA).exists(), isFalse);
    expect(await File(photoB).exists(), isFalse);
    expect(await DatabaseService.instance.getCustomerById(customerId), isNull);
    expect(
      await DatabaseService.instance.getCustomerPhotos(customerId),
      isEmpty,
    );
  });
}

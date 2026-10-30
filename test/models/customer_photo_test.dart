import 'package:berber_randevu/models/customer_photo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer photo map round-trip preserves type and source', () {
    final photo = CustomerPhoto(
      id: 8,
      customerId: 3,
      photoPath: '/database/photos/customer_8.jpg',
      type: CustomerPhotoType.result,
      source: CustomerPhotoSource.camera,
      createdAt: DateTime(2026, 9, 27, 10, 30),
    );

    final restored = CustomerPhoto.fromMap(photo.toMap());

    expect(restored.id, 8);
    expect(restored.customerId, 3);
    expect(restored.type, CustomerPhotoType.result);
    expect(restored.source, CustomerPhotoSource.camera);
    expect(restored.photoPath, photo.photoPath);
  });

  test('unknown photo type and source use safe defaults', () {
    final restored = CustomerPhoto.fromMap({
      'id': 1,
      'customerId': 2,
      'photoPath': '/database/photos/customer.jpg',
      'type': 'future_type',
      'source': 'future_source',
      'createdAt': '2026-09-27T10:30:00.000',
    });

    expect(restored.type, CustomerPhotoType.reference);
    expect(restored.source, CustomerPhotoSource.gallery);
  });
}

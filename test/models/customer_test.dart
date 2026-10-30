import 'package:berber_randevu/models/customer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer map round-trip preserves nullable photoPath', () {
    final customer = Customer(
      id: 12,
      name: 'Fotoğraflı Müşteri',
      phone: '05000000000',
      notes: 'Not korunmalı',
      favoriteHairstyle: 'Yanlar kısa',
      photoPath: '/database/photos/customer-12.jpg',
      totalAppointments: 4,
      lastAppointmentDate: DateTime(2026, 9, 20),
      createdAt: DateTime(2026, 9, 1, 10),
    );

    final restored = Customer.fromMap(customer.toMap());

    expect(restored.photoPath, customer.photoPath);
    expect(restored.notes, customer.notes);
    expect(restored.favoriteHairstyle, customer.favoriteHairstyle);
  });

  test('customer copyWith can clear photoPath', () {
    final customer = Customer(
      name: 'Fotoğraflı Müşteri',
      photoPath: '/database/photos/customer.jpg',
    );

    final updated = customer.copyWith(photoPath: null, clearPhotoPath: true);

    expect(updated.photoPath, isNull);
  });
}

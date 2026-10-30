import 'package:berber_randevu/models/barber_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service round-trips duration price and active state', () {
    final service = BarberService(
      id: 3,
      name: 'Saç + Sakal',
      durationMinutes: 45,
      priceCents: 75000,
      isActive: false,
    );

    final restored = BarberService.fromMap(service.toMap());

    expect(restored.id, 3);
    expect(restored.name, 'Saç + Sakal');
    expect(restored.durationMinutes, 45);
    expect(restored.priceCents, 75000);
    expect(restored.isActive, isFalse);
  });

  test('service rejects non-positive duration and negative price', () {
    expect(
      () => BarberService(name: 'Geçersiz', durationMinutes: 0),
      throwsArgumentError,
    );
    expect(
      () =>
          BarberService(name: 'Geçersiz', durationMinutes: 30, priceCents: -1),
      throwsArgumentError,
    );
  });

  test('editing keeps an archived appointment service selected', () {
    final services = [
      BarberService(id: 1, name: 'Saç', durationMinutes: 30),
      BarberService(
        id: 2,
        name: 'Eski Paket',
        durationMinutes: 60,
        isActive: false,
      ),
    ];

    expect(selectServiceForAppointment(services, 2)?.id, 2);
    expect(selectServiceForAppointment(services, null)?.id, 1);
  });
}

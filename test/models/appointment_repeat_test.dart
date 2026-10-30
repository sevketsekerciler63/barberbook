import 'package:berber_randevu/models/appointment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repeat template keeps customer and appointment details but clears slot',
    () {
      final original = Appointment(
        id: 42,
        customerId: 9,
        customerName: 'Tekrar Müşterisi',
        appointmentDate: DateTime(2026, 9, 20),
        appointmentTime: '14:30',
        hairstyleId: 'fade',
        hairstyleName: 'Fade',
        serviceId: 3,
        serviceName: 'Saç + Sakal',
        durationMinutes: 45,
        priceCents: 50000,
        notes: 'Yanlar kısa kalsın',
        status: AppointmentStatus.completed,
      );

      final repeat = original.repeatTemplate;

      expect(repeat.id, isNull);
      expect(repeat.customerId, original.customerId);
      expect(repeat.customerName, original.customerName);
      expect(repeat.serviceId, original.serviceId);
      expect(repeat.hairstyleName, original.hairstyleName);
      expect(repeat.notes, original.notes);
      expect(repeat.appointmentTime, isNull);
      expect(repeat.status, AppointmentStatus.planned);
    },
  );
}

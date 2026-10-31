import '../models/appointment.dart';
import 'database_service.dart';

/// A fresh snapshot so edited, removed or deleted numbers cannot stay cached.
class CustomerPhoneService {
  static Future<Map<int, String>> load(
    Iterable<Appointment> appointments,
  ) async {
    final ids = appointments.map((a) => a.customerId).whereType<int>().toSet();
    final phones = <int, String>{};
    for (final id in ids) {
      final customer = await DatabaseService.instance.getCustomerById(id);
      final phone = customer?.phone;
      if (phone != null && phone.trim().isNotEmpty) phones[id] = phone;
    }
    return phones;
  }
}

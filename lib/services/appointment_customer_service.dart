import '../models/customer.dart';
import 'database_service.dart';

/// Resolves the customer explicitly selected or entered in an appointment form.
class AppointmentCustomerService {
  static Future<Customer> resolve({
    int? selectedCustomerId,
    required String name,
    required String phone,
  }) async {
    final db = DatabaseService.instance;
    final normalizedName = name.trim();
    final normalizedPhone = phone.trim();
    Customer? customer;
    if (selectedCustomerId != null) {
      customer = await db.getCustomerById(selectedCustomerId);
      if (customer == null) throw StateError('Seçilen müşteri bulunamadı.');
    } else {
      if (normalizedName.isEmpty) throw ArgumentError('Müşteri adı gerekli.');
    }
    if (customer == null) {
      final created = Customer(
        name: normalizedName,
        phone: normalizedPhone.isEmpty ? null : normalizedPhone,
      );
      final id = await db.insertCustomer(created);
      return created.copyWith(id: id);
    }
    if (normalizedPhone.isNotEmpty && customer.phone != normalizedPhone) {
      customer = customer.copyWith(phone: normalizedPhone);
      await db.updateCustomer(customer);
    }
    return customer;
  }
}

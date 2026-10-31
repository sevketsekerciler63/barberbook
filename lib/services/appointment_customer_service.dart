import '../models/customer.dart';
import 'database_service.dart';

class AppointmentCustomerService {
  static Future<Customer> resolve({
    int? selectedCustomerId,
    required String name,
    required String phone,
  }) => DatabaseService.instance.resolveAppointmentCustomer(
    selectedCustomerId: selectedCustomerId,
    name: name,
    phone: phone,
  );
}

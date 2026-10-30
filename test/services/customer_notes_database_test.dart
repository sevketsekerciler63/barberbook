import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/database_service.dart';
import '../test_helpers/database_test_isolation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final isolation = DatabaseTestIsolation();

  setUp(isolation.setUp);

  tearDown(isolation.tearDown);

  test('customer notes persist through insert and edit', () async {
    final customerId = await DatabaseService.instance.insertCustomer(
      Customer(name: 'Notlu Müşteri', notes: 'İlk not'),
    );
    final saved = await DatabaseService.instance.getCustomerById(customerId);

    expect(saved!.notes, 'İlk not');

    await DatabaseService.instance.updateCustomer(
      saved.copyWith(notes: 'Güncellenmiş not'),
    );
    final updated = await DatabaseService.instance.getCustomerById(customerId);

    expect(updated!.notes, 'Güncellenmiş not');
    expect(updated.name, 'Notlu Müşteri');
  });
}

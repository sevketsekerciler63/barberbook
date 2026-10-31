import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/screens/add_appointment_screen.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:berber_randevu/widgets/customer_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  setUp(() async {
    await isolation.setUp();
    await initializeDateFormatting('tr_TR');
  });
  tearDown(isolation.tearDown);

  Future<void> settleDatabase(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  for (final dayOffset in [-120, 730]) {
    testWidgets(
      'existing appointment date outside new-booking window remains editable: $dayOffset',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final date = DateTime.now().add(Duration(days: dayOffset));
        await tester.pumpWidget(
          MaterialApp(
            home: AddAppointmentScreen(
              appointmentToEdit: Appointment(
                id: 7,
                customerName: 'Eski kayıt',
                appointmentDate: date,
                appointmentTime: '10:00',
              ),
            ),
          ),
        );
        await settleDatabase(tester);
        final dateButton = find.text(
          DateFormat('d MMMM yyyy, EEEE', 'tr_TR').format(date),
        );
        await tester.ensureVisible(dateButton);
        await tester.tap(dateButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('clearing the search reports an empty customer name', (
    tester,
  ) async {
    String? reportedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerSearchWidget(
            initialValue: 'Eski seçim',
            onCustomerSelected: (_) {},
            onNewCustomerName: (value) => reportedName = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(reportedName, '');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('editing the name clears the selection before search finishes', (
    tester,
  ) async {
    String? reportedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomerSearchWidget(
            onCustomerSelected: (_) {},
            onNewCustomerName: (value) => reportedName = value,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Yeni isim');
    expect(reportedName, 'Yeni isim');
    await settleDatabase(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'appointment form saves a namesake without changing existing customer',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = DatabaseService.instance;
      final oldId = (await tester.runAsync(
        () => db.insertCustomer(
          Customer(
            name: 'Ahmet Yılmaz',
            phone: '05000000001',
            photoPath: '/existing.jpg',
          ),
        ),
      ))!;
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.pumpWidget(
        MaterialApp(home: AddAppointmentScreen(initialDate: tomorrow)),
      );
      await settleDatabase(tester);
      await tester.enterText(find.byType(TextField).first, 'Ahmet Yılmaz');
      await settleDatabase(tester);
      // Do not choose the suggestion: this is a different person with the same name.
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Telefon (Opsiyonel)',
        ),
        '05000000002',
      );
      await tester.tap(find.text('Lütfen saat belirleyin...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bitti'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('RANDEVU OLUŞTUR'));
      await tester.tap(find.text('RANDEVU OLUŞTUR'));
      // A second tap before the SQLite work completes must not create a duplicate.
      await tester.tap(find.text('RANDEVU OLUŞTUR'));
      await settleDatabase(tester);
      await tester.runAsync(() async {
        var appointments = await db.getAppointmentsByDate(tomorrow);
        for (var attempt = 0; appointments.isEmpty && attempt < 30; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          appointments = await db.getAppointmentsByDate(tomorrow);
        }
        expect(appointments, hasLength(1));
        expect(appointments.single.customerId, isNot(oldId));
        final old = (await db.getCustomerById(oldId))!;
        expect(old.phone, '05000000001');
        expect(old.photoPath, '/existing.jpg');
        expect((await db.getAllCustomers()).length, 2);
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
}

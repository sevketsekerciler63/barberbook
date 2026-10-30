import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/screens/receivables_screen.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'focused collection input can close safely and records only one partial collection',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = DatabaseService.instance;
      final id = (await tester.runAsync(() async {
        final id = await db.insertAppointment(
          Appointment(
            customerName: 'Borçlu Deneme',
            appointmentDate: DateTime(2026, 10, 31),
            appointmentTime: '10:00',
          ),
        );
        await db.completeAppointmentWithPayment(
          id,
          Payment(
            appointmentId: id,
            amountCents: 50000,
            status: PaymentStatus.pending,
            method: PaymentMethod.credit,
          ),
        );
        return id;
      }))!;
      await tester.pumpWidget(const MaterialApp(home: ReceivablesScreen()));
      await settleIo(tester);
      await tester.tap(find.text('Borçlu Deneme'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '150');
      await tester.tap(find.text('Tahsilatı kaydet'));
      await settleIo(tester);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        expect(await db.getOutstandingBalanceForAppointment(id), 35000);
        expect(await db.getPaymentTransactionsForAppointment(id), hasLength(1));
      });
      expect(find.text('350.00 ₺'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

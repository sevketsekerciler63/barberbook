import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/cash_report.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/models/payment_transaction.dart';
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

  test(
    'recompleting a rescheduled credit appointment preserves debt and collections',
    () async {
      final service = DatabaseService.instance;
      final id = await _insertAppointment(await service.database);
      await service.completeAppointmentWithPayment(
        id,
        Payment(
          appointmentId: id,
          amountCents: 50000,
          status: PaymentStatus.pending,
          method: PaymentMethod.credit,
        ),
      );
      await service.recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: id,
          type: PaymentTransactionType.collection,
          amountCents: 15000,
          method: PaymentMethod.cash,
          occurredAt: DateTime.now(),
        ),
      );
      await service.setAppointmentStatus(id, AppointmentStatus.planned);
      await service.completeAppointmentWithoutPayment(id);
      expect(
        (await service.getAppointmentById(id))!.status,
        AppointmentStatus.completed,
      );
      expect(
        (await service.getPaymentForAppointment(id))!.status,
        PaymentStatus.pending,
      );
      expect(await service.getOutstandingBalanceForAppointment(id), 35000);
      expect(
        await service.getPaymentTransactionsForAppointment(id),
        hasLength(1),
      );
    },
  );

  test(
    'credit with partial collections cannot be overwritten as a paid payment',
    () async {
      final service = DatabaseService.instance;
      final id = await _insertAppointment(await service.database);
      await service.completeAppointmentWithPayment(
        id,
        Payment(
          appointmentId: id,
          amountCents: 50000,
          status: PaymentStatus.pending,
          method: PaymentMethod.credit,
        ),
      );
      await service.recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: id,
          type: PaymentTransactionType.collection,
          amountCents: 15000,
          method: PaymentMethod.cash,
          occurredAt: DateTime(2026, 10, 31),
        ),
      );
      await expectLater(
        service.completeAppointmentWithPayment(
          id,
          Payment(
            appointmentId: id,
            amountCents: 50000,
            status: PaymentStatus.paid,
            method: PaymentMethod.card,
            paidAt: DateTime(2026, 10, 31),
          ),
        ),
        throwsStateError,
      );
      expect(
        (await service.getPaymentForAppointment(id))!.status,
        PaymentStatus.pending,
      );
      expect(await service.getOutstandingBalanceForAppointment(id), 35000);
      final report = await service.getCashReport(
        DateTime(2026, 10, 31),
        DateTime(2026, 10, 31),
      );
      expect(report.collectedCents, 15000);
      expect(report.outstandingCents, 35000);
    },
  );

  test('credit method cannot be recorded as a collection', () async {
    final service = DatabaseService.instance;
    final id = await _insertAppointment(await service.database);
    await service.completeAppointmentWithPayment(
      id,
      Payment(
        appointmentId: id,
        amountCents: 10000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
    );
    await expectLater(
      service.recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: id,
          type: PaymentTransactionType.collection,
          amountCents: 1000,
          method: PaymentMethod.credit,
          occurredAt: DateTime.now(),
        ),
      ),
      throwsStateError,
    );
    expect(await service.getOutstandingBalanceForAppointment(id), 10000);
  });

  test(
    'foreign keys are enabled and deleting appointment cascades payment',
    () async {
      final db = await DatabaseService.instance.database;
      final appointmentId = await _insertAppointment(db);
      await DatabaseService.instance.savePayment(
        Payment(
          appointmentId: appointmentId,
          amountCents: 50000,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          paidAt: DateTime(2026, 9, 21, 10),
        ),
      );

      final foreignKeyRows = await db.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeyRows.single.values.single, 1);
      await db.delete(
        'appointments',
        where: 'id = ?',
        whereArgs: [appointmentId],
      );
      expect(await db.query('payments'), isEmpty);
    },
  );

  test(
    'complete with payment is atomic and keeps one payment identity',
    () async {
      final db = await DatabaseService.instance.database;
      final appointmentId = await _insertAppointment(db);

      await DatabaseService.instance.completeAppointmentWithPayment(
        appointmentId,
        Payment(
          appointmentId: appointmentId,
          amountCents: 50000,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          paidAt: DateTime(2026, 9, 21, 10),
        ),
      );
      final first = await DatabaseService.instance.getPaymentForAppointment(
        appointmentId,
      );

      await DatabaseService.instance.completeAppointmentWithPayment(
        appointmentId,
        Payment(
          appointmentId: appointmentId,
          amountCents: 60000,
          status: PaymentStatus.paid,
          method: PaymentMethod.card,
          paidAt: DateTime(2026, 9, 21, 11),
        ),
      );
      final second = await DatabaseService.instance.getPaymentForAppointment(
        appointmentId,
      );
      final appointment = await DatabaseService.instance.getAppointmentById(
        appointmentId,
      );

      expect(appointment!.status, AppointmentStatus.completed);
      expect(second!.id, first!.id);
      expect(second.amountCents, 60000);
      expect(second.method, PaymentMethod.card);
      expect((await db.query('payments')).length, 1);
    },
  );

  test('payment setting defaults to enabled and can be disabled', () async {
    await DatabaseService.instance.database;

    expect(await DatabaseService.instance.isPaymentEnabled(), isTrue);
    await DatabaseService.instance.setPaymentEnabled(false);
    expect(await DatabaseService.instance.isPaymentEnabled(), isFalse);
    await DatabaseService.instance.setPaymentEnabled(true);
    expect(await DatabaseService.instance.isPaymentEnabled(), isTrue);
  });

  test(
    'completion without a payment record preserves optional payment flow',
    () async {
      final db = await DatabaseService.instance.database;
      final appointmentId = await _insertAppointment(db);

      await DatabaseService.instance.completeAppointmentWithoutPayment(
        appointmentId,
      );

      final appointment = await DatabaseService.instance.getAppointmentById(
        appointmentId,
      );
      expect(appointment!.status, AppointmentStatus.completed);
      expect(
        await DatabaseService.instance.getPaymentForAppointment(appointmentId),
        isNull,
      );
    },
  );

  test('partial collections append and reduce outstanding balance', () async {
    final db = await DatabaseService.instance.database;
    final appointmentId = await _insertAppointment(db);
    await DatabaseService.instance.completeAppointmentWithPayment(
      appointmentId,
      Payment(
        appointmentId: appointmentId,
        amountCents: 50000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
    );

    await DatabaseService.instance.recordPaymentTransaction(
      PaymentTransaction(
        appointmentId: appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: 20000,
        method: PaymentMethod.cash,
        occurredAt: DateTime(2026, 9, 21, 12),
      ),
    );
    await DatabaseService.instance.recordPaymentTransaction(
      PaymentTransaction(
        appointmentId: appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: 10000,
        method: PaymentMethod.card,
        occurredAt: DateTime(2026, 9, 21, 13),
      ),
    );

    final transactions = await DatabaseService.instance
        .getPaymentTransactionsForAppointment(appointmentId);
    final outstanding = await DatabaseService.instance
        .getOutstandingBalanceForAppointment(appointmentId);

    expect(transactions, hasLength(2));
    expect(transactions.map((item) => item.amountCents), [20000, 10000]);
    expect(outstanding, 20000);
  });

  test('collection cannot exceed outstanding credit', () async {
    final db = await DatabaseService.instance.database;
    final appointmentId = await _insertAppointment(db);
    await DatabaseService.instance.completeAppointmentWithPayment(
      appointmentId,
      Payment(
        appointmentId: appointmentId,
        amountCents: 30000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
    );

    expect(
      () => DatabaseService.instance.recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: appointmentId,
          type: PaymentTransactionType.collection,
          amountCents: 40000,
          method: PaymentMethod.cash,
          occurredAt: DateTime(2026, 9, 21, 12),
        ),
      ),
      throwsStateError,
    );
  });

  test('open receivables reflect partial and full collections', () async {
    final db = await DatabaseService.instance.database;
    final appointmentId = await _insertAppointment(db);
    await DatabaseService.instance.completeAppointmentWithPayment(
      appointmentId,
      Payment(
        appointmentId: appointmentId,
        amountCents: 30000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
    );

    var receivables = await DatabaseService.instance.getOpenReceivables();
    expect(receivables.single.outstandingCents, 30000);
    expect(receivables.single.customerName, 'Test Müşterisi');

    await DatabaseService.instance.recordPaymentTransaction(
      PaymentTransaction(
        appointmentId: appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: 10000,
        method: PaymentMethod.cash,
        occurredAt: DateTime(2026, 9, 21, 12),
      ),
    );
    receivables = await DatabaseService.instance.getOpenReceivables();
    expect(receivables.single.outstandingCents, 20000);

    await DatabaseService.instance.recordPaymentTransaction(
      PaymentTransaction(
        appointmentId: appointmentId,
        type: PaymentTransactionType.collection,
        amountCents: 20000,
        method: PaymentMethod.card,
        occurredAt: DateTime(2026, 9, 21, 13),
      ),
    );
    expect(await DatabaseService.instance.getOpenReceivables(), isEmpty);
  });

  test(
    'cash report uses inclusive date range and current outstanding total',
    () async {
      final db = await DatabaseService.instance.database;
      final appointmentId = await _insertAppointment(
        db,
        date: DateTime(2026, 9, 10),
      );
      await DatabaseService.instance.completeAppointmentWithPayment(
        appointmentId,
        Payment(
          appointmentId: appointmentId,
          amountCents: 50000,
          status: PaymentStatus.pending,
          method: PaymentMethod.credit,
        ),
      );
      await DatabaseService.instance.recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: appointmentId,
          type: PaymentTransactionType.collection,
          amountCents: 15000,
          method: PaymentMethod.transfer,
          occurredAt: DateTime(2026, 9, 21, 23, 59),
        ),
      );

      final CashReport report = await DatabaseService.instance.getCashReport(
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 21),
      );

      expect(report.collectedCents, 15000);
      expect(report.outstandingCents, 35000);
      expect(report.byMethod[PaymentMethod.transfer], 15000);
    },
  );

  test(
    'cash summary uses paidAt and ignores non-completed appointments',
    () async {
      final db = await DatabaseService.instance.database;
      final appointmentId = await _insertAppointment(
        db,
        date: DateTime(2026, 9, 10),
      );
      await DatabaseService.instance.completeAppointmentWithPayment(
        appointmentId,
        Payment(
          appointmentId: appointmentId,
          amountCents: 50000,
          status: PaymentStatus.paid,
          method: PaymentMethod.cash,
          paidAt: DateTime(2026, 9, 21, 15),
        ),
      );

      expect(
        (await DatabaseService.instance.getPaymentsForDate(
          DateTime(2026, 9, 21),
        )).length,
        1,
      );
      expect(
        await DatabaseService.instance.getPaymentsForDate(
          DateTime(2026, 9, 10),
        ),
        isEmpty,
      );

      await DatabaseService.instance.setAppointmentStatus(
        appointmentId,
        AppointmentStatus.cancelled,
      );
      expect(
        await DatabaseService.instance.getPaymentsForDate(
          DateTime(2026, 9, 21),
        ),
        isEmpty,
      );
    },
  );
}

Future<int> _insertAppointment(Database db, {DateTime? date}) {
  return db.insert('appointments', {
    'customerId': null,
    'customerName': 'Test Müşterisi',
    'appointmentDate': (date ?? DateTime(2026, 9, 21)).toIso8601String(),
    'appointmentTime': '10:00',
    'durationMinutes': 30,
    'isCompleted': 0,
    'status': 'planned',
    'createdAt': DateTime(2026, 9, 20).toIso8601String(),
  });
}

import 'dart:io';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/models/payment_transaction.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:berber_randevu/services/backup_service.dart';
import 'package:berber_randevu/services/cash_report_csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  final db = DatabaseService.instance;
  final originalDay = DateTime(2026, 11, 2, 10);
  final refundDay = DateTime(2026, 11, 3, 11);
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);
  Future<int> account({
    bool credit = false,
    int amount = 50000,
    int tip = 2000,
  }) async {
    final id = await db.insertAppointment(
      Appointment(
        customerName: 'İade Müşterisi',
        appointmentDate: originalDay,
        appointmentTime: '10:00',
      ),
    );
    await db.completeAppointmentWithPayment(
      id,
      Payment(
        appointmentId: id,
        amountCents: amount,
        tipCents: credit ? 0 : tip,
        status: credit ? PaymentStatus.pending : PaymentStatus.paid,
        method: credit ? PaymentMethod.credit : PaymentMethod.cash,
        paidAt: credit ? null : originalDay,
      ),
    );
    return id;
  }

  PaymentTransaction correction(
    int id,
    int amount, {
    String key = 'refund-1',
    int tip = 0,
    PaymentTransactionType type = PaymentTransactionType.refund,
    String note = 'Yanlış tutar düzeltmesi',
    PaymentMethod? method,
  }) => PaymentTransaction(
    appointmentId: id,
    type: type,
    amountCents: amount,
    tipCents: tip,
    operationId: key,
    note: note,
    occurredAt: refundDay,
    method:
        method ??
        (type == PaymentTransactionType.adjustment
            ? PaymentMethod.other
            : PaymentMethod.cash),
  );
  Future<void> collect(int id, int amount) => db
      .recordPaymentTransaction(
        PaymentTransaction(
          appointmentId: id,
          type: PaymentTransactionType.collection,
          amountCents: amount,
          method: PaymentMethod.card,
          occurredAt: originalDay,
        ),
      )
      .then((_) {});

  test(
    'refund keeps original row and affects only refund day including separate tips and CSV',
    () async {
      final id = await account();
      final original = (await db.getPaymentForAppointment(id))!.toMap();
      await db.recordPaymentCorrection(correction(id, 10500, tip: 500));
      expect((await db.getPaymentForAppointment(id))!.toMap(), original);
      final state = (await db.getPaymentAccount(id))!;
      expect(state.refundableServiceCents, 40000);
      expect(state.refundableTipCents, 1500);
      final before = await db.getCashReport(originalDay, originalDay);
      final today = await db.getCashReport(refundDay, refundDay);
      expect(before.collectedCents, 50000);
      expect(before.tipCents, 2000);
      expect(before.refundCount, 0);
      expect(today.collectedCents, 0);
      expect(today.refundedCents, 10000);
      expect(today.refundedTipCents, 500);
      expect(today.netServiceCents, -10000);
      expect(today.netTipCents, -500);
      expect(today.netCashCents, -10500);
      expect(today.byMethod[PaymentMethod.cash], -10000);
      final csv = CashReportCsv.build(today, refundDay, refundDay);
      expect(csv, contains('Net hizmet;-100,00'));
      expect(csv, contains('Bahşiş iadesi;5,00'));
      expect(csv, contains('Net para hareketi;-105,00'));
    },
  );
  test(
    'independent service and tip caps hold and tip-only refund is allowed',
    () async {
      final id = await account();
      await expectLater(
        db.recordPaymentCorrection(correction(id, 50001)),
        throwsStateError,
      );
      await expectLater(
        db.recordPaymentCorrection(correction(id, 2001, tip: 2001)),
        throwsStateError,
      );
      await db.recordPaymentCorrection(correction(id, 50000));
      await db.recordPaymentCorrection(
        correction(id, 2000, tip: 2000, key: 'tip-only'),
      );
      final state = (await db.getPaymentAccount(id))!;
      expect(state.refundableServiceCents, 0);
      expect(state.refundableTipCents, 0);
      await expectLater(
        db.recordPaymentCorrection(correction(id, 1, key: 'extra')),
        throwsStateError,
      );
      expect((await db.getCashReport(originalDay, refundDay)).netCashCents, 0);
    },
  );
  test(
    'reason, operation identity, type and real payment method are mandatory',
    () async {
      final id = await account();
      await expectLater(
        db.recordPaymentCorrection(correction(id, 100, note: '   ')),
        throwsArgumentError,
      );
      await expectLater(
        db.recordPaymentCorrection(correction(id, 100, key: '')),
        throwsArgumentError,
      );
      await expectLater(
        db.recordPaymentCorrection(
          correction(id, 100, method: PaymentMethod.credit),
        ),
        throwsArgumentError,
      );
      await expectLater(
        db.recordPaymentCorrection(
          correction(id, 100, type: PaymentTransactionType.collection),
        ),
        throwsArgumentError,
      );
      expect((await db.getPaymentAccount(id))!.transactions, isEmpty);
    },
  );
  test(
    'same operation is recorded once across concurrent retries and database reopen',
    () async {
      final id = await account();
      final request = correction(id, 10000);
      final ids = await Future.wait(
        List.generate(3, (_) => db.recordPaymentCorrection(request)),
      );
      expect(ids.toSet(), hasLength(1));
      await db.closeDatabase();
      expect(await db.recordPaymentCorrection(request), ids.first);
      expect((await db.getPaymentAccount(id))!.transactions, hasLength(1));
      await expectLater(
        db.recordPaymentCorrection(correction(id, 11000)),
        throwsStateError,
      );
      final other = await account();
      await expectLater(
        db.recordPaymentCorrection(correction(other, 10000)),
        throwsStateError,
      );
    },
  );
  test(
    'distinct concurrent refunds cannot jointly exceed remaining cash',
    () async {
      final id = await account();
      Future<bool> attempt(String key) async {
        try {
          await db.recordPaymentCorrection(correction(id, 30000, key: key));
          return true;
        } on StateError {
          return false;
        }
      }

      final outcomes = await Future.wait([attempt('a'), attempt('b')]);
      expect(outcomes.where((v) => v), hasLength(1));
      expect((await db.getPaymentAccount(id))!.refundableServiceCents, 20000);
    },
  );
  test(
    'partial credit refund does not recreate debt; write-off reduces only unpaid balance',
    () async {
      final id = await account(credit: true, amount: 30000);
      await collect(id, 10000);
      await db.recordPaymentCorrection(correction(id, 4000));
      var item = (await db.getOpenReceivables()).single;
      expect(item.outstandingCents, 20000);
      expect(item.refundedCents, 4000);
      final waiver = correction(
        id,
        5000,
        key: 'waiver',
        type: PaymentTransactionType.adjustment,
      );
      await db.recordPaymentCorrection(waiver);
      item = (await db.getOpenReceivables()).single;
      expect(item.outstandingCents, 15000);
      expect(item.waivedCents, 5000);
      expect(await db.getOutstandingBalanceForAppointment(id), 15000);
      await expectLater(collect(id, 16000), throwsStateError);
      await collect(id, 15000);
      expect(await db.getOpenReceivables(), isEmpty);
      await expectLater(
        db.recordPaymentCorrection(
          correction(
            id,
            1,
            key: 'excess-waiver',
            type: PaymentTransactionType.adjustment,
          ),
        ),
        throwsStateError,
      );
      expect(
        (await db.getCashReport(originalDay, refundDay)).netServiceCents,
        21000,
      );
      expect(
        (await db.getPaymentForAppointment(id))!.status,
        PaymentStatus.pending,
      );
    },
  );
  test(
    'unpaid full write-off has no cash movement and retries remain idempotent',
    () async {
      final id = await account(credit: true, amount: 30000);
      final request = correction(
        id,
        30000,
        type: PaymentTransactionType.adjustment,
      );
      final first = await db.recordPaymentCorrection(request);
      expect(await db.recordPaymentCorrection(request), first);
      expect(await db.getOpenReceivables(), isEmpty);
      final report = await db.getCashReport(refundDay, refundDay);
      expect(report.netCashCents, 0);
      expect(report.waivedDebtCents, 30000);
      expect(report.byMethod, isEmpty);
      await expectLater(
        db.recordPaymentCorrection(correction(id, 1, key: 'no-money')),
        throwsStateError,
      );
    },
  );
  test(
    'financial appointment deletion is refused and Turkish history search finds the account',
    () async {
      final id = await account();
      await expectLater(db.deleteAppointment(id), throwsStateError);
      expect(await db.getAppointmentById(id), isNotNull);
      expect(
        (await db.getPaymentAccounts(query: 'IADE')).single.appointmentId,
        id,
      );
      expect(
        (await db.getPaymentAccounts(query: '$id')).single.appointmentId,
        id,
      );
    },
  );

  test(
    'legacy unknown and already-refunded payments cannot generate new refunds',
    () async {
      for (final status in [PaymentStatus.unknown, PaymentStatus.refunded]) {
        final id = await db.insertAppointment(
          Appointment(
            customerName: 'Eski kayıt',
            appointmentDate: originalDay,
            appointmentTime: '12:00',
          ),
        );
        await db.savePayment(
          Payment(
            appointmentId: id,
            amountCents: 50000,
            status: status,
            method: PaymentMethod.cash,
          ),
        );
        await expectLater(
          db.recordPaymentCorrection(
            correction(id, 100, key: 'legacy-${status.name}'),
          ),
          throwsStateError,
        );
        expect((await db.getPaymentAccount(id))!.transactions, isEmpty);
      }
    },
  );
  test(
    'v12 upgrade preserves original payment and collection then permits a correction',
    () async {
      final id = await account(credit: true);
      await collect(id, 10000);
      final connection = await db.database;
      await connection.execute('DROP INDEX idx_payment_operation');
      await connection.execute('DROP INDEX idx_payment_reversal');
      await connection.execute(
        'ALTER TABLE payment_transactions DROP COLUMN reversesTransactionId',
      );
      await connection.execute(
        'ALTER TABLE payment_transactions DROP COLUMN operationId',
      );
      await connection.execute(
        'ALTER TABLE payment_transactions DROP COLUMN tipCents',
      );
      await connection.setVersion(12);
      await db.closeDatabase();
      final upgraded = await db.database;
      expect(await upgraded.getVersion(), 14);
      final state = (await db.getPaymentAccount(id))!;
      expect(state.outstandingCents, 40000);
      expect(state.transactions.single.tipCents, 0);
      expect(state.transactions.single.operationId, isNull);
      await db.recordPaymentCorrection(correction(id, 1000));
      expect((await db.getPaymentAccount(id))!.refundableServiceCents, 9000);
    },
  );
  test(
    'v13 ZIP backup restores correction ledger, tips and persistent retry identity',
    () async {
      final id = await account();
      final request = correction(id, 10500, tip: 500);
      final first = await db.recordPaymentCorrection(request);
      final backup = await BackupService.instance.createBackup();
      expect(
        (await BackupService.instance.previewBackup(backup)).schemaVersion,
        14,
      );
      await db.recordPaymentCorrection(correction(id, 1000, key: 'later'));
      await BackupService.instance.restoreBackup(backup);
      expect((await db.getPaymentAccount(id))!.transactions, hasLength(1));
      expect(await db.recordPaymentCorrection(request), first);
      expect((await db.getPaymentAccount(id))!.refundableTipCents, 1500);
    },
  );
  test(
    'v13 backup declaring corrections but missing their fields is rejected',
    () async {
      await account();
      await db.closeDatabase();
      final bad = await File(
        isolation.databasePath,
      ).copy('${isolation.databasePath}.bad13');
      final connection = await openDatabase(bad.path, singleInstance: false);
      await connection.execute('DROP INDEX idx_payment_operation');
      await connection.execute(
        'ALTER TABLE payment_transactions DROP COLUMN operationId',
      );
      await connection.close();
      await expectLater(
        BackupService.instance.validateBackup(bad),
        throwsStateError,
      );
      expect((await db.getPaymentAccounts()), hasLength(1));
    },
  );
  PaymentTransaction undo(
    int id,
    int movementId,
    int amount, {
    int tip = 0,
    String key = 'undo',
    PaymentTransactionType type = PaymentTransactionType.refund,
    PaymentMethod? method,
  }) => PaymentTransaction(
    appointmentId: id,
    type: type,
    amountCents: amount,
    tipCents: tip,
    operationId: key,
    reversesTransactionId: movementId,
    note: 'Yanlış düzeltmeyi geri alma',
    occurredAt: DateTime(2026, 11, 4, 12),
    method:
        method ??
        (type == PaymentTransactionType.adjustment
            ? PaymentMethod.other
            : PaymentMethod.cash),
  );

  test(
    'refund reversal preserves both entries, restores caps and survives backup with retry identity',
    () async {
      final id = await account();
      final original = await db.recordPaymentCorrection(
        correction(id, 10500, tip: 500),
      );
      final request = undo(id, original, 10500, tip: 500);
      final inverse = await db.recordPaymentCorrection(request);
      var state = (await db.getPaymentAccount(id))!;
      expect(state.transactions, hasLength(2));
      expect(state.refundableServiceCents, 50000);
      expect(state.refundableTipCents, 2000);
      expect(
        (await db.getCashReport(refundDay, refundDay)).netCashCents,
        -10500,
      );
      final reverseDay = DateTime(2026, 11, 4);
      final report = await db.getCashReport(reverseDay, reverseDay);
      expect(report.refundedCents, -10000);
      expect(report.refundedTipCents, -500);
      expect(report.netCashCents, 10500);
      final backup = await BackupService.instance.createBackup();
      await BackupService.instance.restoreBackup(backup);
      expect(await db.recordPaymentCorrection(request), inverse);
      state = (await db.getPaymentAccount(id))!;
      expect(state.transactions.last.reversesTransactionId, original);
      expect(state.transactions, hasLength(2));
    },
  );
  test(
    'write-off reversal reopens only debt and cannot reverse the reversal',
    () async {
      final id = await account(credit: true, amount: 30000);
      await collect(id, 10000);
      final original = await db.recordPaymentCorrection(
        correction(id, 20000, type: PaymentTransactionType.adjustment),
      );
      expect(await db.getOpenReceivables(), isEmpty);
      final request = undo(
        id,
        original,
        20000,
        type: PaymentTransactionType.adjustment,
      );
      final inverse = await db.recordPaymentCorrection(request);
      expect((await db.getOpenReceivables()).single.outstandingCents, 20000);
      expect((await db.getOpenReceivables()).single.waivedCents, 0);
      expect(
        (await db.getCashReport(
          DateTime(2026, 11, 4),
          DateTime(2026, 11, 4),
        )).netCashCents,
        0,
      );
      await expectLater(
        db.recordPaymentCorrection(
          undo(
            id,
            inverse,
            20000,
            type: PaymentTransactionType.adjustment,
            key: 'undo-again',
          ),
        ),
        throwsStateError,
      );
      await collect(id, 20000);
      expect(await db.getOpenReceivables(), isEmpty);
    },
  );
  test(
    'reversal must match the original and distinct concurrent reversals can succeed only once',
    () async {
      final id = await account();
      final original = await db.recordPaymentCorrection(correction(id, 10000));
      await expectLater(
        db.recordPaymentCorrection(undo(id, original, 9999)),
        throwsStateError,
      );
      await expectLater(
        db.recordPaymentCorrection(
          undo(id, original, 10000, method: PaymentMethod.card),
        ),
        throwsStateError,
      );
      Future<bool> attempt(String key) async {
        try {
          await db.recordPaymentCorrection(undo(id, original, 10000, key: key));
          return true;
        } on StateError {
          return false;
        }
      }

      expect(
        (await Future.wait([
          attempt('undo-a'),
          attempt('undo-b'),
        ])).where((v) => v),
        hasLength(1),
      );
      expect((await db.getPaymentAccount(id))!.transactions, hasLength(2));
      expect((await db.getPaymentAccount(id))!.refundableServiceCents, 50000);
    },
  );
}

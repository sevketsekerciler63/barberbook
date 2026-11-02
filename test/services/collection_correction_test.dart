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
  final day = DateTime(2026, 11, 3, 10), next = DateTime(2026, 11, 4, 12);
  setUp(isolation.setUp);
  tearDown(isolation.tearDown);
  Future<int> credit() async {
    final id = await db.insertAppointment(
      Appointment(
        customerName: 'Tahsilat Deneme',
        appointmentDate: day,
        appointmentTime: '10:00',
      ),
    );
    await db.completeAppointmentWithPayment(
      id,
      Payment(
        appointmentId: id,
        amountCents: 30000,
        status: PaymentStatus.pending,
        method: PaymentMethod.credit,
      ),
    );
    return id;
  }

  PaymentTransaction collection(
    int id,
    int amount,
    String key, {
    PaymentMethod method = PaymentMethod.cash,
    DateTime? at,
  }) => PaymentTransaction(
    appointmentId: id,
    type: PaymentTransactionType.collection,
    amountCents: amount,
    method: method,
    occurredAt: at ?? day,
    operationId: key,
  );
  PaymentTransaction reverse(
    int id,
    int origin,
    String key, {
    int amount = 10000,
    PaymentTransactionType type = PaymentTransactionType.collection,
    PaymentMethod method = PaymentMethod.cash,
  }) => PaymentTransaction(
    appointmentId: id,
    type: type,
    amountCents: amount,
    method: method,
    occurredAt: next,
    operationId: key,
    reversesTransactionId: origin,
    note: 'Yanlış kayıt düzeltmesi',
  );

  test(
    'collection retries are idempotent before and after full settlement and reopen',
    () async {
      final id = await credit();
      final request = collection(id, 10000, 'first');
      final ids = await Future.wait(
        List.generate(3, (_) => db.recordPaymentTransaction(request)),
      );
      expect(ids.toSet(), hasLength(1));
      expect(await db.getOutstandingBalanceForAppointment(id), 20000);
      final remaining = collection(id, 20000, 'remaining');
      final last = await db.recordPaymentTransaction(remaining);
      await db.closeDatabase();
      expect(await db.recordPaymentTransaction(remaining), last);
      expect(await db.getOutstandingBalanceForAppointment(id), 0);
      expect((await db.getPaymentTransactionsForAppointment(id)), hasLength(2));
      await expectLater(
        db.recordPaymentTransaction(collection(id, 20000, 'first')),
        throwsStateError,
      );
      await expectLater(
        db.recordPaymentTransaction(
          collection(id, 10000, 'first', method: PaymentMethod.card),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'collection reversal reopens debt and records negative cash on its own day; replacement fixes method totals',
    () async {
      final id = await credit();
      final original = (await db.getPaymentForAppointment(id))!.toMap();
      final movement = await db.recordPaymentTransaction(
        collection(id, 10000, 'cash'),
      );
      final request = reverse(id, movement, 'undo');
      final inverse = await db.recordPaymentCorrection(request);
      expect(await db.recordPaymentCorrection(request), inverse);
      var item = (await db.getOpenReceivables()).single;
      expect(item.outstandingCents, 30000);
      expect(item.collectedCents, 0);
      expect(item.refundedCents, 0);
      final report = await db.getCashReport(next, next);
      expect(report.collectedCents, 0);
      expect(report.reversedCollectionCents, 10000);
      expect(report.netCashCents, -10000);
      expect(report.collectionReversalCount, 1);
      expect(report.byMethod[PaymentMethod.cash], -10000);
      expect(
        CashReportCsv.build(report, next, next),
        contains('Tahsilat geri alma;100,00'),
      );
      await db.recordPaymentTransaction(
        collection(
          id,
          10000,
          'correct-card',
          method: PaymentMethod.card,
          at: next,
        ),
      );
      item = (await db.getOpenReceivables()).single;
      expect(item.outstandingCents, 20000);
      final all = await db.getCashReport(day, next);
      expect(all.collectedCents, 20000);
      expect(all.netServiceCents, 10000);
      expect(all.byMethod[PaymentMethod.cash], 0);
      expect(all.byMethod[PaymentMethod.card], 10000);
      expect((await db.getPaymentForAppointment(id))!.toMap(), original);
    },
  );
  test(
    'refunded cash cannot be reversed as a collection until its refund is undone',
    () async {
      final id = await credit();
      final original = await db.recordPaymentTransaction(
        collection(id, 10000, 'collect'),
      );
      final refund = await db.recordPaymentCorrection(
        PaymentTransaction(
          appointmentId: id,
          type: PaymentTransactionType.refund,
          amountCents: 4000,
          method: PaymentMethod.cash,
          occurredAt: day,
          operationId: 'refund',
          note: 'Para iadesi',
        ),
      );
      await expectLater(
        db.recordPaymentCorrection(reverse(id, original, 'undo-collection')),
        throwsStateError,
      );
      await db.recordPaymentCorrection(
        reverse(
          id,
          refund,
          'undo-refund',
          amount: 4000,
          type: PaymentTransactionType.refund,
        ),
      );
      await db.recordPaymentCorrection(
        reverse(id, original, 'undo-collection'),
      );
      expect(await db.getOutstandingBalanceForAppointment(id), 30000);
      expect((await db.getPaymentAccount(id))!.refundableServiceCents, 0);
      expect((await db.getCashReport(day, next)).netCashCents, 0);
    },
  );
  test(
    'concurrent collection reversals cannot reopen the same debt twice',
    () async {
      final id = await credit();
      final origin = await db.recordPaymentTransaction(
        collection(id, 10000, 'original'),
      );
      Future<bool> attempt(String key) async {
        try {
          await db.recordPaymentCorrection(reverse(id, origin, key));
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
      expect(await db.getOutstandingBalanceForAppointment(id), 30000);
      expect((await db.getPaymentTransactionsForAppointment(id)), hasLength(2));
      final inverse = (await db.getPaymentTransactionsForAppointment(id)).last;
      await expectLater(
        db.recordPaymentCorrection(reverse(id, inverse.id!, 'undo-undo')),
        throwsStateError,
      );
    },
  );
  test(
    'distinct concurrent collections cannot exceed debt and invalid API types cannot bypass lookup',
    () async {
      final id = await credit();
      Future<bool> collect(String key) async {
        try {
          await db.recordPaymentTransaction(collection(id, 20000, key));
          return true;
        } on StateError {
          return false;
        }
      }

      expect(
        (await Future.wait([collect('a'), collect('b')])).where((v) => v),
        hasLength(1),
      );
      expect(await db.getOutstandingBalanceForAppointment(id), 10000);
      final request = PaymentTransaction(
        appointmentId: id,
        type: PaymentTransactionType.refund,
        amountCents: 1000,
        method: PaymentMethod.cash,
        occurredAt: next,
        operationId: 'refund',
        note: 'Hatalı tutar',
      );
      await db.recordPaymentCorrection(request);
      await expectLater(db.recordPaymentTransaction(request), throwsStateError);
    },
  );
  test(
    'v13 upgrade preserves history; v14 backup keeps reversal semantics and retry key',
    () async {
      final id = await credit();
      final original = await db.recordPaymentTransaction(
        collection(id, 10000, 'legacy'),
      );
      await (await db.database).setVersion(13);
      await db.closeDatabase();
      expect(await (await db.database).getVersion(), 14);
      expect(await db.getOutstandingBalanceForAppointment(id), 20000);
      final request = reverse(id, original, 'undo');
      final reversedId = await db.recordPaymentCorrection(request);
      final backup = await BackupService.instance.createBackup();
      expect(
        (await BackupService.instance.previewBackup(backup)).schemaVersion,
        14,
      );
      await BackupService.instance.restoreBackup(backup);
      expect(await db.recordPaymentCorrection(request), reversedId);
      expect(await db.getOutstandingBalanceForAppointment(id), 30000);
      expect((await db.getCashReport(day, next)).netCashCents, 0);
    },
  );
}

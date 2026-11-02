import 'dart:async';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/models/payment_account.dart';
import 'package:berber_randevu/models/payment_transaction.dart';
import 'package:berber_randevu/screens/payment_correction_dialog.dart';
import 'package:berber_randevu/screens/payment_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PaymentAccount _account({bool credit = false, int amount = 50000}) =>
    PaymentAccount(
      payment: Payment(
        appointmentId: 42,
        amountCents: amount,
        tipCents: credit ? 0 : 2000,
        status: credit ? PaymentStatus.pending : PaymentStatus.paid,
        method: credit ? PaymentMethod.credit : PaymentMethod.cash,
      ),
      customerName: 'Test müşterisi',
      appointmentDate: DateTime(2026, 11, 3),
      transactions: const [],
    );

class _Ledger extends PaymentLedgerGateway {
  PaymentAccount account = _account();
  final requests = <PaymentTransaction>[];
  Future<int> Function(PaymentTransaction)? save;
  @override
  Future<PaymentAccount?> get(int id) async => account;
  @override
  Future<int> record(PaymentTransaction request) async {
    requests.add(request);
    if (save != null) return save!(request);
    return 1;
  }
}

void main() {
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> dialog(
    WidgetTester tester,
    PaymentAccount account,
    PaymentTransactionType type,
    void Function(PaymentTransaction?) result, {
    bool large = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: large
            ? (_, child) => MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
                child: child!,
              )
            : null,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result(
                  await showPaymentCorrectionDialog(context, account, type),
                );
              },
              child: const Text('İşlemi aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('İşlemi aç'));
    await tester.pumpAndSettle();
  }

  Future<void> confirmRefund(
    WidgetTester tester, {
    void Function(DateTime)? beforeConfirm,
  }) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Para iadesi'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Hizmet iadesi (₺)'), '100');
    await tester.enterText(field('Gerekçe (zorunlu)'), 'Hatalı tutar');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(find.text('Para iadesini kaydet'), findsOneWidget);
    beforeConfirm?.call(DateTime.now());
    await tester.tap(find.text('Onayla ve kaydet'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'refund requires reason and valid component caps then returns precise cents',
    (tester) async {
      PaymentTransaction? result;
      await dialog(
        tester,
        _account(),
        PaymentTransactionType.refund,
        (v) => result = v,
      );
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(
        find.text('Geçerli bir tutar ve işlem gerekçesi girin.'),
        findsOneWidget,
      );
      await tester.enterText(field('Gerekçe (zorunlu)'), '  Fazla tahsilat  ');
      await tester.enterText(field('Hizmet iadesi (₺)'), '600');
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tutar kalan iade veya veresiye sınırını aşamaz.'),
        findsOneWidget,
      );
      await tester.enterText(field('Hizmet iadesi (₺)'), '100,25');
      await tester.enterText(field('Bahşiş iadesi (₺)'), '1,25');
      await tester.tap(find.text('Kart'));
      await tester.pump();
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(result!.amountCents, 10150);
      expect(result!.tipCents, 125);
      expect(result!.serviceCents, 10025);
      expect(result!.method, PaymentMethod.card);
      expect(result!.note, 'Fazla tahsilat');
      expect(result!.operationId, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'write-off has no cash method or tip field and records a reason',
    (tester) async {
      PaymentTransaction? result;
      await dialog(
        tester,
        _account(credit: true),
        PaymentTransactionType.adjustment,
        (v) => result = v,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(field('Bahşiş iadesi (₺)'), findsNothing);
      await tester.enterText(field('Borçtan düşülecek tutar (₺)'), '50');
      await tester.enterText(field('Gerekçe (zorunlu)'), 'Yanlış yazılan borç');
      await tester.tap(find.text('Devam'));
      await tester.pumpAndSettle();
      expect(result!.amountCents, 5000);
      expect(result!.method, PaymentMethod.other);
      expect(result!.type, PaymentTransactionType.adjustment);
      expect(result!.tipCents, 0);
    },
  );
  testWidgets('tip-only refund is possible with zero service amount', (
    tester,
  ) async {
    PaymentTransaction? result;
    await dialog(
      tester,
      _account(amount: 0),
      PaymentTransactionType.refund,
      (v) => result = v,
    );
    await tester.enterText(field('Bahşiş iadesi (₺)'), '5');
    await tester.enterText(field('Gerekçe (zorunlu)'), 'Bahşiş iadesi');
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(result!.amountCents, 500);
    expect(result!.serviceCents, 0);
    expect(result!.tipCents, 500);
  });
  testWidgets(
    'failed save retries exactly the same confirmed operation identity',
    (tester) async {
      final ledger = _Ledger();
      ledger.save = (request) async {
        if (ledger.requests.length == 1) throw StateError('transient');
        ledger.account = PaymentAccount(
          payment: ledger.account.payment,
          customerName: ledger.account.customerName,
          appointmentDate: ledger.account.appointmentDate,
          transactions: [request],
        );
        return 1;
      };
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentAccountScreen(appointmentId: 42, ledger: ledger),
        ),
      );
      await tester.pump();
      DateTime? confirmationStarted;
      await confirmRefund(
        tester,
        beforeConfirm: (value) => confirmationStarted = value,
      );
      expect(
        ledger.requests.first.occurredAt.isBefore(confirmationStarted!),
        isFalse,
      );
      expect(ledger.requests.first.createdAt, ledger.requests.first.occurredAt);
      expect(find.text('Aynı işlemi yeniden dene'), findsOneWidget);
      await tester.tap(find.text('Aynı işlemi yeniden dene'));
      await tester.pumpAndSettle();
      expect(ledger.requests, hasLength(2));
      expect(ledger.requests[0].operationId, ledger.requests[1].operationId);
      expect(ledger.requests[0].occurredAt, ledger.requests[1].occurredAt);
      expect(find.text('Düzeltme hareketi kaydedildi.'), findsOneWidget);
      expect(
        find.textContaining('Kalan hizmet iadesi: 400.00'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending confirmed save blocks duplicates and completion after disposal is safe',
    (tester) async {
      final pending = Completer<int>();
      final ledger = _Ledger()..save = (_) => pending.future;
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentAccountScreen(appointmentId: 42, ledger: ledger),
        ),
      );
      await tester.pump();
      await confirmRefund(tester);
      expect(ledger.requests, hasLength(1));
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Para iadesi'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete(1);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('correction form fits narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await dialog(
      tester,
      _account(),
      PaymentTransactionType.refund,
      (_) {},
      large: true,
    );
    await tester.ensureVisible(field('Gerekçe (zorunlu)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'reversal form requires reason and preserves original identity and amount',
    (tester) async {
      final original = PaymentTransaction(
        id: 7,
        appointmentId: 42,
        type: PaymentTransactionType.adjustment,
        amountCents: 5000,
        method: PaymentMethod.other,
        occurredAt: DateTime(2026, 11, 3),
      );
      PaymentTransaction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showPaymentReversalDialog(context, original);
                },
                child: const Text('Geri al'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Geri al'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('müşterinin açık borcu bu tutarda artar'),
        findsOneWidget,
      );
      await tester.tap(find.text('Geri alma hareketini kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Geri alma gerekçesi girin.'), findsOneWidget);
      await tester.enterText(
        field('Geri alma gerekçesi (zorunlu)'),
        'Yanlış müşteri',
      );
      await tester.tap(find.text('Geri alma hareketini kaydet'));
      await tester.pumpAndSettle();
      expect(result!.reversesTransactionId, 7);
      expect(result!.amountCents, 5000);
      expect(result!.method, PaymentMethod.other);
      expect(result!.operationId, isNotEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'collection reversal explains the reopened debt and preserves the original movement',
    (tester) async {
      final original = PaymentTransaction(
        id: 8,
        appointmentId: 42,
        type: PaymentTransactionType.collection,
        amountCents: 10000,
        method: PaymentMethod.card,
        occurredAt: DateTime(2026, 11, 3),
      );
      PaymentTransaction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showPaymentReversalDialog(context, original);
                },
                child: const Text('Tahsilat iptal'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tahsilat iptal'));
      await tester.pumpAndSettle();
      expect(find.text('Tahsilatı geri al'), findsOneWidget);
      expect(
        find.textContaining('aynı tutar yeniden açık borç olur'),
        findsOneWidget,
      );
      await tester.enterText(
        field('Geri alma gerekçesi (zorunlu)'),
        'Yanlış ödeme yöntemi',
      );
      await tester.tap(find.text('Geri alma hareketini kaydet'));
      await tester.pumpAndSettle();
      expect(result!.reversesTransactionId, 8);
      expect(result!.type, PaymentTransactionType.collection);
      expect(result!.amountCents, 10000);
      expect(result!.method, PaymentMethod.card);
    },
  );
}

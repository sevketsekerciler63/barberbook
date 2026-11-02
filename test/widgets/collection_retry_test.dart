import 'dart:async';
import 'package:berber_randevu/models/payment_transaction.dart';
import 'package:berber_randevu/models/receivable.dart';
import 'package:berber_randevu/screens/receivables_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway extends ReceivablesGateway {
  int remaining = 50000;
  final requests = <PaymentTransaction>[];
  Future<int> Function(PaymentTransaction)? save;
  @override
  Future<List<Receivable>> load() async => remaining == 0
      ? []
      : [
          Receivable(
            appointmentId: 42,
            customerName: 'Borçlu',
            serviceName: 'Kesim',
            appointmentDate: DateTime(2026, 11, 3),
            originalAmountCents: 50000,
            collectedCents: 50000 - remaining,
            outstandingCents: remaining,
          ),
        ];
  @override
  Future<int> record(PaymentTransaction request) async {
    requests.add(request);
    if (save != null) return save!(request);
    remaining -= request.amountCents;
    return 1;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Gateway gateway, {
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
        home: ReceivablesScreen(gateway: gateway),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Borçlu'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '150');
    await tester.tap(find.text('Tahsilatı kaydet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets(
    'lost commit response retries the same collection and reloads the saved balance',
    (tester) async {
      final gateway = _Gateway();
      gateway.save = (request) async {
        if (gateway.requests.length == 1) {
          gateway.remaining -= request.amountCents;
          throw StateError('Yanıt alınamadı');
        }
        return 1;
      };
      await show(tester, gateway);
      await open(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Aynı tahsilatı yeniden dene'), findsOneWidget);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Borçlu')).onTap,
        isNull,
      );
      await tester.tap(find.text('Aynı tahsilatı yeniden dene'));
      await tester.pumpAndSettle();
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.first.operationId, isNotNull);
      expect(
        gateway.requests.first.operationId,
        gateway.requests.last.operationId,
      );
      expect(
        gateway.requests.first.occurredAt,
        gateway.requests.last.occurredAt,
      );
      expect(gateway.remaining, 35000);
      expect(find.text('350.00 ₺'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending collection disables another submit and safely completes after disposal',
    (tester) async {
      final pending = Completer<int>();
      final gateway = _Gateway()..save = (_) => pending.future;
      await show(tester, gateway);
      await open(tester);
      await submit(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Borçlu')).onTap,
        isNull,
      );
      expect(gateway.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      pending.complete(1);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancel unlocks collection; narrow large-text error can refresh before a new attempt',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway()
        ..save = (_) async => throw StateError('İşlem doğrulanamadı');
      await show(tester, gateway, large: true);
      await open(tester);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(gateway.requests, isEmpty);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isTrue);
      await open(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Listeyi yenile'));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Borçlu')).onTap,
        isNotNull,
      );
      expect(gateway.requests, hasLength(1));
    },
  );
}

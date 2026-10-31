import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/payment.dart';
import 'package:berber_randevu/screens/payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Payment? result;
  Future<void> open(WidgetTester tester, {Payment? existing}) async {
    result = null;
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPaymentDialog(
                  context,
                  Appointment(
                    id: 7,
                    customerName: 'Deneme',
                    appointmentDate: DateTime(2026, 10, 31),
                    appointmentTime: '10:00',
                    priceCents: 50000,
                  ),
                  existing: existing,
                );
              },
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String label, String value) async {
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  testWidgets('credit creates net debt without cash collection', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, 'İndirim (₺)', '50,25');
    await tester.tap(find.text('Veresiye'));
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result!.amountCents, 44975);
    expect(result!.discountCents, 5025);
    expect(result!.status, PaymentStatus.pending);
    expect(result!.method, PaymentMethod.credit);
    expect(result!.paidAt, isNull);
  });

  testWidgets('cash records discount tip and note independently', (
    tester,
  ) async {
    await open(tester);
    await enter(tester, 'İndirim (₺)', '50');
    await enter(tester, 'Bahşiş (₺, hizmet bedelinden ayrı)', '20,50');
    await enter(tester, 'Ödeme notu (opsiyonel)', 'Örnek not');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(result!.amountCents, 45000);
    expect(result!.tipCents, 2050);
    expect(result!.discountCents, 5000);
    expect(result!.note, 'Örnek not');
    expect(result!.status, PaymentStatus.paid);
    expect(result!.paidAt, isNotNull);
  });

  testWidgets(
    'invalid and excessive values stay in the dialog without crashing',
    (tester) async {
      await open(tester);
      await enter(tester, 'Hizmet bedeli (indirim öncesi, ₺)', 'NaN');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.textContaining('Tutarları en fazla'), findsOneWidget);
      await enter(tester, 'Hizmet bedeli (indirim öncesi, ₺)', '100');
      await enter(tester, 'İndirim (₺)', '101');
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing debt directs user to collections instead of overwriting',
    (tester) async {
      await open(
        tester,
        existing: Payment(
          appointmentId: 7,
          amountCents: 50000,
          status: PaymentStatus.pending,
          method: PaymentMethod.credit,
        ),
      );
      expect(find.text('Kayıtlı veresiye'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Veresiyelere git'), findsOneWidget);
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets('a paid record is read-only and offers no credit conversion', (
    tester,
  ) async {
    final paidAt = DateTime(2026, 10, 1);
    await open(
      tester,
      existing: Payment(
        id: 3,
        appointmentId: 7,
        amountCents: 45000,
        discountCents: 5000,
        tipCents: 1000,
        note: 'Eski not',
        status: PaymentStatus.paid,
        method: PaymentMethod.card,
        paidAt: paidAt,
      ),
    );
    expect(find.text('Tahsilat zaten kayıtlı'), findsOneWidget);
    expect(find.text('Veresiye'), findsNothing);
    expect(find.text('Kaydet'), findsNothing);
    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}

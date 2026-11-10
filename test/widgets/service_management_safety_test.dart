import 'dart:async';
import 'package:berber_randevu/models/barber_service.dart';
import 'package:berber_randevu/screens/service_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway extends ServiceManagementGateway {
  Future<List<BarberService>> Function()? onLoad;
  Future<void> Function(BarberService)? onSave;
  int saves = 0;
  final saved = <BarberService>[];
  @override
  Future<List<BarberService>> load() async =>
      onLoad == null ? [] : await onLoad!();
  @override
  Future<void> save(BarberService service) async {
    saves++;
    saved.add(service);
    await onSave?.call(service);
  }
}

void main() {
  Future<void> show(WidgetTester tester, _Gateway gateway) async {
    await tester.pumpWidget(
      MaterialApp(home: ServiceManagementScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Hizmet adı'),
      'Saç kesimi',
    );
  }

  testWidgets('load error is retryable without claiming empty services', (
    tester,
  ) async {
    var calls = 0;
    final gateway = _Gateway()
      ..onLoad = () async {
        if (calls++ == 0) throw StateError('read failed');
        return [BarberService(id: 1, name: 'Sakal', durationMinutes: 15)];
      };
    await show(tester, gateway);
    expect(find.text('Hizmetler yüklenemedi.'), findsOneWidget);
    expect(find.text('Henüz hizmet eklenmedi.'), findsNothing);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Tekrar dene'));
    await tester.pumpAndSettle();
    expect(find.text('Sakal'), findsOneWidget);
  });

  testWidgets('double save and back are blocked until one write completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final gateway = _Gateway()..onSave = (_) => pending.future;
    await show(tester, gateway);
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Fiyat (₺, opsiyonel)'),
      '125,50',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(gateway.saves, 1);
    expect(gateway.saved.single.priceCents, 12550);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    await Navigator.of(tester.element(find.byType(AlertDialog))).maybePop();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Hizmet adı'))
          .enabled,
      isFalse,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('write error keeps entered values and retry saves once more', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..onSave = (_) async =>
          throw StateError('Aynı adlı aktif hizmet zaten var.');
    await show(tester, gateway);
    await open(tester);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(find.text('Aynı adlı aktif hizmet zaten var.'), findsOneWidget);
    expect(find.text('Saç kesimi'), findsOneWidget);
    gateway.onSave = (_) async {};
    await tester.enterText(
      find.widgetWithText(TextField, 'Hizmet adı'),
      'Saç ve sakal',
    );
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(gateway.saves, 2);
    expect(gateway.saved.last.name, 'Saç ve sakal');
    expect(gateway.saved.last.priceCents, isNull);
  });

  testWidgets(
    'invalid fractional, nonfinite and excessive prices never write',
    (tester) async {
      final gateway = _Gateway();
      await show(tester, gateway);
      await open(tester);
      for (final text in [
        '12,345',
        'NaN',
        'Infinity',
        '99999999999',
        '-1',
        '1e3',
      ]) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Fiyat (₺, opsiyonel)'),
          text,
        );
        await tester.tap(find.text('Kaydet'));
        await tester.pump();
        expect(
          find.text('Fiyatı en fazla iki ondalık basamakla girin.'),
          findsOneWidget,
        );
        expect(gateway.saves, 0);
      }
      await tester.enterText(
        find.widgetWithText(TextField, 'Fiyat (₺, opsiyonel)'),
        '0',
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(gateway.saved.single.priceCents, 0);
    },
  );

  testWidgets(
    'late save result after screen disposal does not update dead state',
    (tester) async {
      final pending = Completer<void>();
      final gateway = _Gateway()..onSave = (_) => pending.future;
      await show(tester, gateway);
      await open(tester);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpWidget(const SizedBox());
      pending.completeError(StateError('late failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editor remains usable at 320dp with large text and can cancel safely',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = _Gateway();
      await show(tester, gateway);
      await open(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(gateway.saves, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

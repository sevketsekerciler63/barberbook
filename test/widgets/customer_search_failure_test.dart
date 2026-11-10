import 'dart:async';

import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/widgets/customer_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget show({
    required Future<List<Customer>> Function(String) search,
    ValueChanged<String>? onName,
    ValueChanged<Customer>? onSelect,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            CustomerSearchWidget(
              search: search,
              onCustomerSelected: onSelect ?? (_) {},
              onNewCustomerName: onName ?? (_) {},
            ),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => FocusScope.of(context).unfocus(),
                child: const Text('Başka alan'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets(
    'failed search can retry without clearing the typed customer again',
    (tester) async {
      final queries = <String>[];
      final names = <String>[];
      final pending = Completer<List<Customer>>();
      Customer? selected;
      await tester.pumpWidget(
        show(
          search: (query) {
            queries.add(query);
            if (queries.length == 1) {
              return Future.error(StateError('unavailable'));
            }
            return pending.future;
          },
          onName: names.add,
          onSelect: (customer) => selected = customer,
        ),
      );
      await tester.enterText(find.byType(TextField), 'Ayşe');
      await tester.pump();
      expect(find.textContaining('Müşteri araması yapılamadı'), findsOneWidget);
      expect(names, ['Ayşe']);
      await tester.tap(find.text('Aramayı yeniden dene'));
      await tester.pump();
      expect(find.text('Müşteriler aranıyor…'), findsOneWidget);
      expect(find.textContaining('Müşteri araması yapılamadı'), findsNothing);
      pending.complete([Customer(id: 4, name: 'Ayşe Yılmaz')]);
      await tester.pump();
      expect(queries, ['Ayşe', 'Ayşe']);
      expect(names, ['Ayşe']);
      await tester.tap(find.text('Ayşe Yılmaz'));
      await tester.pump();
      expect(selected?.id, 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old query error cannot replace a newer successful result', (
    tester,
  ) async {
    final old = Completer<List<Customer>>();
    await tester.pumpWidget(
      show(
        search: (query) => query == 'A'
            ? old.future
            : Future.value([Customer(id: 8, name: 'Yeni sonuç')]),
      ),
    );
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump();
    expect(find.text('Müşteriler aranıyor…'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'B');
    await tester.pump();
    old.completeError(StateError('old failure'));
    await tester.pump();
    expect(find.text('Yeni sonuç'), findsOneWidget);
    expect(find.textContaining('Müşteri araması yapılamadı'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clearing reports empty name immediately and suppresses pending results',
    (tester) async {
      final pending = Completer<List<Customer>>();
      final names = <String>[];
      await tester.pumpWidget(
        show(search: (_) => pending.future, onName: names.add),
      );
      await tester.enterText(find.byType(TextField), 'Ahmet');
      await tester.pump();
      await tester.tap(find.byTooltip('Müşteri seçimini temizle'));
      expect(names, ['Ahmet', '']);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      pending.complete([Customer(id: 1, name: 'Ahmet Eski')]);
      await tester.pump();
      expect(find.text('Ahmet Eski'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late search cannot reopen suggestions after focus leaves the field',
    (tester) async {
      final pending = Completer<List<Customer>>();
      var calls = 0;
      await tester.pumpWidget(
        show(
          search: (_) {
            calls++;
            return calls == 1
                ? pending.future
                : Future.value([Customer(id: 2, name: 'Ayşe Yeni')]);
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'Ayşe');
      await tester.tap(find.text('Başka alan'));
      await tester.pump();
      pending.complete([Customer(id: 1, name: 'Ayşe Eski')]);
      await tester.pump();
      expect(find.text('Ayşe Eski'), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Ayşe Yeni'), findsOneWidget);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'disposal safely ignores late ${fails ? 'failure' : 'success'}',
      (tester) async {
        final pending = Completer<List<Customer>>();
        await tester.pumpWidget(show(search: (_) => pending.future));
        await tester.enterText(find.byType(TextField), 'Ayşe');
        await tester.pumpWidget(const SizedBox());
        if (fails) {
          pending.completeError(StateError('late'));
        } else {
          pending.complete([Customer(id: 1, name: 'Ayşe')]);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('retry feedback fits narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      show(search: (_) async => throw StateError('failed')),
    );
    await tester.enterText(find.byType(TextField), 'Ayşe');
    await tester.pump();
    expect(find.text('Aramayı yeniden dene'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

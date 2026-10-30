import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/screens/customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('customer add form accepts notes up to the supported limit', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CustomerNotesField(controller: controller)),
      ),
    );

    final notesField = find.widgetWithText(
      TextField,
      'Müşteri Notu (Opsiyonel)',
    );
    expect(notesField, findsOneWidget);

    await tester.enterText(notesField, 'n' * Customer.maxNotesLength);
    await tester.pump();

    expect(controller.text.length, Customer.maxNotesLength);
  });

  testWidgets('customer detail displays saved notes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomerNotesSection(notes: 'Makine 2 numara tercih ediyor'),
        ),
      ),
    );

    expect(find.text('Müşteri Notu'), findsOneWidget);
    expect(find.text('Makine 2 numara tercih ediyor'), findsOneWidget);
  });
}

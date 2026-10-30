import 'package:berber_randevu/screens/working_hours_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows and changes the parallel appointment capacity', (
    tester,
  ) async {
    int? selectedCapacity;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentCapacityPicker(
            currentCapacity: 1,
            onSelected: (value) => selectedCapacity = value,
          ),
        ),
      ),
    );

    expect(find.text('Aynı anda müşteri sayısı'), findsOneWidget);
    expect(find.text('1 müşteri'), findsOneWidget);

    await tester.tap(find.text('2 müşteri'));
    await tester.pump();

    expect(selectedCapacity, 2);
  });
}

import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/screens/alarm_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final appointment = Appointment(
    id: 42,
    customerName: 'Test Müşterisi',
    appointmentDate: DateTime(2026, 9, 27),
    appointmentTime: '10:00',
    createdAt: DateTime(2026, 9, 26),
  );

  testWidgets('alarm presents acknowledgement and optional payment actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlarmScreen(appointment: appointment, paymentEnabled: true),
      ),
    );

    expect(find.text('Kapat'), findsOneWidget);
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.text('Ödeme al'), findsOneWidget);
  });

  testWidgets('alarm hides payment action when payment records are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AlarmScreen(appointment: appointment, paymentEnabled: false),
      ),
    );

    expect(find.text('Kapat'), findsOneWidget);
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.text('Ödeme al'), findsNothing);
  });
}

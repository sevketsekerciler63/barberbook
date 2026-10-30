import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/widgets/appointment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Appointment appointmentWith(AppointmentStatus status) => Appointment(
    id: 7,
    customerName: 'Şevket Işık',
    appointmentDate: DateTime.now().add(const Duration(days: 1)),
    appointmentTime: '14:00',
    serviceName: 'Saç Kesimi',
    status: status,
  );

  Future<void> pumpCard(WidgetTester tester, AppointmentStatus status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentCard(appointment: appointmentWith(status)),
        ),
      ),
    );
  }

  testWidgets('no-show appointment card visibly shows Gelmedi status', (
    tester,
  ) async {
    await pumpCard(tester, AppointmentStatus.noShow);

    expect(find.text('Gelmedi'), findsOneWidget);
  });

  testWidgets('cancelled appointment card visibly shows İptal edildi status', (
    tester,
  ) async {
    await pumpCard(tester, AppointmentStatus.cancelled);

    expect(find.text('İptal edildi'), findsOneWidget);
  });

  testWidgets(
    'planned appointment card does not show an inactive status chip',
    (tester) async {
      await pumpCard(tester, AppointmentStatus.planned);

      expect(find.text('Gelmedi'), findsNothing);
      expect(find.text('İptal edildi'), findsNothing);
    },
  );

  testWidgets('card fits a narrow phone with all quick actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppointmentCard(
            appointment: appointmentWith(AppointmentStatus.planned),
            customerPhone: '05551234567',
            onCall: () {},
            onWhatsApp: () {},
            onComplete: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  for (final status in [
    AppointmentStatus.cancelled,
    AppointmentStatus.noShow,
  ]) {
    testWidgets('inactive $status keeps contact actions but hides completion', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppointmentCard(
              appointment: appointmentWith(status),
              onCall: () {},
              onWhatsApp: () {},
              onComplete: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('Müşteriyi ara'), findsOneWidget);
      expect(find.byTooltip('WhatsApp mesajı hazırla'), findsOneWidget);
      expect(find.byTooltip('Randevuyu tamamla'), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);
    });
  }

  testWidgets('card fits 320dp width with large system text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          home: Scaffold(
            body: AppointmentCard(
              appointment: Appointment(
                id: 8,
                customerName: 'Çok Uzun Müşteri Adı Soyadı Denemesi',
                appointmentDate: DateTime.now().add(const Duration(days: 1)),
                appointmentTime: '09:40',
                serviceName: 'Saç Sakal Bakım ve Özel Model Uygulaması',
                status: AppointmentStatus.planned,
              ),
              customerPhone: '05551234567',
              onCall: () {},
              onWhatsApp: () {},
              onComplete: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Müşteriyi ara'), findsOneWidget);
    expect(find.byTooltip('WhatsApp mesajı hazırla'), findsOneWidget);
    expect(find.byTooltip('Randevuyu tamamla'), findsOneWidget);
    expect(find.textContaining('Saç Sakal Bakım'), findsOneWidget);
    expect(find.textContaining('30 dk'), findsOneWidget);
    final timeFinder = find.text('09:40');
    final timeText = tester.widget<Text>(timeFinder);
    final timePainter = TextPainter(
      text: TextSpan(text: '09:40', style: timeText.style),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.5),
      maxLines: 1,
    )..layout();

    expect(tester.getSize(timeFinder).height, lessThan(45));
    expect(
      tester.getSize(timeFinder).width,
      greaterThanOrEqualTo(timePainter.width),
    );

    for (final tooltip in [
      'Müşteriyi ara',
      'WhatsApp mesajı hazırla',
      'Randevuyu tamamla',
    ]) {
      final button = find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });
}

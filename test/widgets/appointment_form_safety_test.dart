import 'dart:async';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/barber_service.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/models/working_schedule.dart';
import 'package:berber_randevu/screens/add_appointment_screen.dart';
import 'package:berber_randevu/services/appointment_form_gateway.dart';
import 'package:berber_randevu/services/alarm_scheduling.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Gateway extends AppointmentFormGateway {
  Future<List<BarberService>> Function()? onServices;
  Future<Customer?> Function()? onCustomer;
  Future<Appointment> Function(Appointment)? onSave;
  Future<AlarmScheduleResult> Function()? onAlarm;
  int saves = 0;
  int alarms = 0;
  @override
  Future<List<BarberService>> services() async => onServices == null
      ? [BarberService(id: 1, name: 'Saç', durationMinutes: 30)]
      : onServices!();
  @override
  Future<Customer?> customer(int id) async => onCustomer == null
      ? Customer(id: id, name: 'Müşteri', phone: '05000000001')
      : onCustomer!();
  @override
  Future<List<WorkingInterval>> workingIntervals() async => [];
  @override
  Future<List<ClosedTimeBlock>> closedBlocks() async => [];
  @override
  Future<bool> isTaken(Appointment appointment, {int? excludeId}) async =>
      false;
  @override
  Future<Appointment> save({
    required Appointment appointment,
    required int? selectedCustomerId,
    required String phone,
    AppointmentStatus? expectedStatus,
  }) async {
    saves++;
    return onSave == null ? appointment : onSave!(appointment);
  }

  @override
  Future<AlarmScheduleResult> syncAlarm(
    Appointment appointment, {
    required bool editing,
  }) async {
    alarms++;
    return onAlarm == null ? AlarmScheduleResult.notRequired : onAlarm!();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  Appointment appointment({String name = 'Müşteri'}) => Appointment(
    id: 10,
    customerId: 3,
    customerName: name,
    serviceId: 1,
    appointmentDate: DateTime.now().subtract(const Duration(days: 1)),
    appointmentTime: '10:00',
    notes: 'Eski not',
  );
  Future<GlobalKey<NavigatorState>> show(
    WidgetTester tester,
    _Gateway gateway, {
    void Function(bool?)? result,
    String name = 'Müşteri',
  }) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: Scaffold(
          body: TextButton(
            onPressed: () async {
              final value = await key.currentState!.push<bool>(
                MaterialPageRoute(
                  builder: (_) => AddAppointmentScreen(
                    gateway: gateway,
                    appointmentToEdit: appointment(name: name),
                  ),
                ),
              );
              result?.call(value);
            },
            child: const Text('Formu aç'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Formu aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    return key;
  }

  testWidgets(
    'load failure can retry; no editable form until all data is ready',
    (tester) async {
      var reads = 0;
      final gateway = _Gateway()
        ..onCustomer = () async {
          if (reads++ == 0) throw StateError('Müşteri yüklenemedi');
          return Customer(id: 3, name: 'Müşteri');
        };
      await show(tester, gateway);
      expect(find.text('Müşteri yüklenemedi'), findsOneWidget);
      expect(find.text('GÜNCELLE'), findsNothing);
      await tester.tap(find.text('Yeniden dene'));
      await tester.pumpAndSettle();
      expect(find.text('GÜNCELLE'), findsOneWidget);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rapid load retries share one request and cannot reset later edits',
    (tester) async {
      final pending = Completer<Customer?>();
      var reads = 0;
      final gateway = _Gateway()
        ..onCustomer = () {
          if (reads++ == 0) {
            return Future.error(StateError('İlk yükleme hatası'));
          }
          return pending.future;
        };
      await show(tester, gateway);
      await tester.tap(find.text('Yeniden dene'));
      await tester.tap(find.text('Yeniden dene'));
      await tester.pump();
      expect(reads, 2);
      pending.complete(Customer(id: 3, name: 'Müşteri'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Yeni not korunur');
      await tester.pump();
      expect(find.text('Yeni not korunur'), findsOneWidget);
      expect(reads, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('late initial load after closing form is ignored', (
    tester,
  ) async {
    final pending = Completer<List<BarberService>>();
    final gateway = _Gateway()..onServices = () => pending.future;
    final key = await show(tester, gateway);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    pending.completeError(StateError('late'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Formu aç'), findsOneWidget);
  });

  testWidgets('dirty back asks; staying preserves text and leaving discards', (
    tester,
  ) async {
    final key = await show(tester, _Gateway());
    await tester.enterText(find.byType(TextField), 'Yeni not');
    await tester.pump();
    key.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsOneWidget);
    await tester.tap(find.text('Düzenlemeye devam et'));
    await tester.pumpAndSettle();
    expect(find.text('Yeni not'), findsOneWidget);
    key.currentState!.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydetmeden çık'));
    await tester.pumpAndSettle();
    expect(find.text('Formu aç'), findsOneWidget);
  });

  testWidgets('unchanged form exits without a warning', (tester) async {
    final key = await show(tester, _Gateway());
    key.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Değişiklikler kaydedilmedi'), findsNothing);
    expect(find.text('Formu aç'), findsOneWidget);
  });

  testWidgets(
    'pending save rejects duplicates and back; success returns true once',
    (tester) async {
      final pending = Completer<Appointment>();
      final gateway = _Gateway()..onSave = (_) => pending.future;
      bool? returned;
      final key = await show(tester, gateway, result: (r) => returned = r);
      await tester.ensureVisible(find.text('GÜNCELLE'));
      await tester.tap(find.text('GÜNCELLE'));
      await tester.tap(find.text('GÜNCELLE'));
      await tester.pump();
      key.currentState!.maybePop();
      await tester.pump();
      expect(find.byType(AddAppointmentScreen), findsOneWidget);
      expect(find.text('Değişiklikler kaydedilmedi'), findsNothing);
      expect(gateway.saves, 1);
      expect(find.text('Randevu kaydediliyor…'), findsOneWidget);
      pending.complete(appointment());
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(gateway.alarms, 1);
    },
  );

  testWidgets('write failure retains edits and unlocks retry', (tester) async {
    var attempts = 0;
    final gateway = _Gateway()
      ..onSave = (a) async {
        if (attempts++ == 0) throw StateError('Depolama kullanılamıyor');
        expect(a.notes, 'Korunan not');
        return a;
      };
    bool? returned;
    await show(tester, gateway, result: (r) => returned = r);
    await tester.enterText(find.byType(TextField), 'Korunan not');
    await tester.ensureVisible(find.text('GÜNCELLE'));
    await tester.tap(find.text('GÜNCELLE'));
    await tester.pumpAndSettle();
    expect(find.text('Korunan not'), findsOneWidget);
    expect(find.text('Depolama kullanılamıyor'), findsWidgets);
    await tester.ensureVisible(find.text('GÜNCELLE'));
    await tester.tap(find.text('GÜNCELLE'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(gateway.saves, 2);
  });

  testWidgets('committed save stays guarded while alarm response is pending', (
    tester,
  ) async {
    final alarm = Completer<AlarmScheduleResult>();
    final gateway = _Gateway()..onAlarm = () => alarm.future;
    bool? returned;
    final key = await show(tester, gateway, result: (r) => returned = r);
    await tester.ensureVisible(find.text('GÜNCELLE'));
    await tester.tap(find.text('GÜNCELLE'));
    await tester.pump();
    // Force an inherited-widget rebuild after the DB commit.
    tester.view.physicalSize = const Size(800, 700);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    key.currentState!.maybePop();
    await tester.pump();
    expect(find.byType(AddAppointmentScreen), findsOneWidget);
    expect(gateway.saves, 1);
    expect(returned, isNull);
    alarm.complete(AlarmScheduleResult.notRequired);
    await tester.pumpAndSettle();
    expect(returned, isTrue);
  });

  testWidgets('long customer name fits narrow large-text edit form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await show(
      tester,
      _Gateway(),
      name: 'Oldukça uzun adı ve soyadı olan müşteri',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alarm failure after committed save still returns success', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..onAlarm = () async => throw StateError('native');
    bool? returned;
    await show(tester, gateway, result: (r) => returned = r);
    await tester.ensureVisible(find.text('GÜNCELLE'));
    await tester.tap(find.text('GÜNCELLE'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(gateway.saves, 1);
    expect(find.textContaining('alarm'), findsWidgets);
  });
  testWidgets('saving a form below a new overlay closes only the form', (
    tester,
  ) async {
    final pending = Completer<Appointment>();
    final gateway = _Gateway()..onSave = (_) => pending.future;
    bool? returned;
    final key = await show(tester, gateway, result: (r) => returned = r);
    await tester.ensureVisible(find.text('GÜNCELLE'));
    await tester.tap(find.text('GÜNCELLE'));
    await tester.pump();
    key.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Alarm üst ekranı')),
      ),
    );
    await tester.pump();
    pending.complete(appointment());
    await tester.pumpAndSettle();
    expect(find.text('Alarm üst ekranı'), findsOneWidget);
    expect(
      find.byType(AddAppointmentScreen, skipOffstage: false),
      findsNothing,
    );
    expect(returned, isTrue);
  });
}

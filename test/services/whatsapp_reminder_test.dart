import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:berber_randevu/services/whatsapp_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/database_test_isolation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final isolation = DatabaseTestIsolation();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await isolation.setUp();
  });
  tearDown(isolation.tearDown);

  Future<AppointmentReminder> pending(WhatsAppService service) async {
    final db = DatabaseService.instance;
    final customerId = await db.insertCustomer(
      Customer(name: 'Deneme', phone: '05000000001'),
    );
    final date = DateTime.now().add(const Duration(minutes: 30));
    await db.insertAppointment(
      Appointment(
        customerId: customerId,
        customerName: 'Deneme',
        appointmentDate: DateTime(date.year, date.month, date.day),
        appointmentTime:
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
      ),
    );
    await service.setAutoReminderEnabled(true);
    return (await service.checkPendingReminders()).single;
  }

  test('failed external launch leaves the reminder pending', () async {
    final service = WhatsAppService(openUrl: (_) async => false);
    final reminder = await pending(service);
    expect(await service.openReminder(reminder), isFalse);
    expect(await service.checkPendingReminders(), hasLength(1));
  });

  test('launch exception leaves the reminder pending', () async {
    final service = WhatsAppService(
      openUrl: (_) async => throw StateError('unavailable'),
    );
    final reminder = await pending(service);
    expect(await service.openReminder(reminder), isFalse);
    expect(await service.checkPendingReminders(), hasLength(1));
  });

  test(
    'opening a prepared message dismisses the reminder and encodes its content',
    () async {
      Uri? opened;
      final service = WhatsAppService(
        openUrl: (uri) async {
          opened = uri;
          return true;
        },
      );
      final reminder = await pending(service);
      expect(await service.openReminder(reminder), isTrue);
      expect(await service.checkPendingReminders(), isEmpty);
      expect(opened!.host, 'wa.me');
      expect(opened!.path, '/905000000001');
      expect(opened!.queryParameters['text'], reminder.message);
    },
  );

  test('explicit skip dismisses without opening any external app', () async {
    var launches = 0;
    final service = WhatsAppService(
      openUrl: (_) async {
        launches++;
        return true;
      },
    );
    final reminder = await pending(service);
    await service.markAsHandled(
      reminder.appointment.id!,
      reminder.reminderType,
    );
    expect(await service.checkPendingReminders(), isEmpty);
    expect(launches, 0);
  });

  test('legacy handled reminders are preserved after upgrade', () async {
    final service = WhatsAppService(openUrl: (_) async => false);
    final reminder = await pending(service);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('wp_sent_reminders', [
      '${reminder.appointment.id}_${reminder.reminderType}',
    ]);
    expect(await service.checkPendingReminders(), isEmpty);
  });
}

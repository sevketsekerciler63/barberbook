import 'dart:async';
import 'package:berber_randevu/models/appointment.dart';
import 'package:berber_randevu/models/customer.dart';
import 'package:berber_randevu/services/database_service.dart';
import 'package:berber_randevu/services/backup_service.dart';
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
    await service.markAsHandled(reminder);
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
    await prefs.remove('wp_handled_reminders_v2');
    await service.prepareReminderHistory();
    expect(await service.checkPendingReminders(), isEmpty);
  });

  test(
    'rescheduling a handled appointment makes its reminder pending again',
    () async {
      final service = WhatsAppService(openUrl: (_) async => true);
      final reminder = await pending(service);
      await service.openReminder(reminder);
      final moved = reminder.appointment.fullDateTime.add(
        const Duration(minutes: 5),
      );
      await DatabaseService.instance.updateAppointment(
        reminder.appointment.copyWith(
          appointmentDate: moved,
          appointmentTime:
              '${moved.hour.toString().padLeft(2, '0')}:${moved.minute.toString().padLeft(2, '0')}',
        ),
      );
      expect(await service.checkPendingReminders(), hasLength(1));
    },
  );

  test(
    'replacement record with the same numeric ID is not dismissed',
    () async {
      final service = WhatsAppService(openUrl: (_) async => true);
      final reminder = await pending(service);
      await service.openReminder(reminder);
      final db = await DatabaseService.instance.database;
      await db.update(
        'appointments',
        {
          'createdAt': reminder.appointment.createdAt
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [reminder.appointment.id],
      );
      expect(await service.checkPendingReminders(), hasLength(1));
    },
  );

  test(
    'a cancelled appointment cannot be opened from a stale dialog',
    () async {
      var launches = 0;
      final service = WhatsAppService(
        openUrl: (_) async {
          launches++;
          return true;
        },
      );
      final reminder = await pending(service);
      await DatabaseService.instance.updateAppointment(
        reminder.appointment.copyWith(status: AppointmentStatus.cancelled),
      );
      expect(await service.openReminder(reminder), isFalse);
      expect(launches, 0);
    },
  );
  test(
    'legacy dismissal stays with its original slot across migration and restart',
    () async {
      final service = WhatsAppService(openUrl: (_) async => true);
      final reminder = await pending(service);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('wp_handled_reminders_v2');
      await prefs.setStringList('wp_sent_reminders', [
        '${reminder.appointment.id}_${reminder.reminderType}',
      ]);
      await service.prepareReminderHistory();
      expect(await service.checkPendingReminders(), isEmpty);
      expect(prefs.containsKey('wp_sent_reminders'), isFalse);
      final moved = reminder.appointment.fullDateTime.add(
        const Duration(minutes: 5),
      );
      await DatabaseService.instance.updateAppointment(
        reminder.appointment.copyWith(
          appointmentDate: moved,
          appointmentTime:
              '${moved.hour.toString().padLeft(2, '0')}:${moved.minute.toString().padLeft(2, '0')}',
        ),
      );
      final restarted = WhatsAppService(openUrl: (_) async => true);
      await restarted.prepareReminderHistory();
      expect(await restarted.checkPendingReminders(), hasLength(1));
      expect(
        prefs.getStringList('wp_handled_reminders_v2')!.single,
        matches(RegExp(r'^v2:[a-f0-9]{64}$')),
      );
    },
  );

  test(
    'real backup restore does not inherit a different record dismissal',
    () async {
      var launches = 0;
      final service = WhatsAppService(
        openUrl: (_) async {
          launches++;
          return true;
        },
      );
      final original = await pending(service);
      final backup = await BackupService.instance.createBackup();
      final connection = await DatabaseService.instance.database;
      await connection.update(
        'appointments',
        {
          'createdAt': original.appointment.createdAt
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [original.appointment.id],
      );
      final replacement = (await service.checkPendingReminders()).single;
      expect(await service.openReminder(replacement), isTrue);
      await BackupService.instance.restoreBackup(backup);
      expect(await service.openReminder(replacement), isFalse);
      expect(launches, 1);
      final restored = (await service.checkPendingReminders()).single;
      expect(restored.appointment.createdAt, original.appointment.createdAt);
      expect(await service.openReminder(restored), isTrue);
      expect(await WhatsAppService().checkPendingReminders(), isEmpty);
    },
  );

  test(
    'startup migration binds legacy dismissal before restoring the database',
    () async {
      final service = WhatsAppService(openUrl: (_) async => false);
      final original = await pending(service);
      final backup = await BackupService.instance.createBackup();
      final connection = await DatabaseService.instance.database;
      await connection.update(
        'appointments',
        {
          'createdAt': original.appointment.createdAt
              .add(const Duration(days: 1))
              .toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [original.appointment.id],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('wp_handled_reminders_v2');
      await prefs.setStringList('wp_sent_reminders', [
        '${original.appointment.id}_${original.reminderType}',
      ]);
      // Both entrypoints migrate before exposing any restore/edit UI, even when disabled.
      await service.setAutoReminderEnabled(false);
      await service.prepareReminderHistory();
      await BackupService.instance.restoreBackup(backup);
      await service.setAutoReminderEnabled(true);
      expect(await service.checkPendingReminders(), hasLength(1));
    },
  );

  test('concurrent skips from service instances retain both choices', () async {
    final service = WhatsAppService();
    final original = await pending(service);
    await DatabaseService.instance.insertAppointment(
      original.appointment.copyWith(id: 999),
    );
    final reminders = await service.checkPendingReminders();
    expect(reminders, hasLength(2));
    await Future.wait([
      service.markAsHandled(reminders.first),
      WhatsAppService().markAsHandled(reminders.last),
    ]);
    expect(await service.checkPendingReminders(), isEmpty);
  });

  test('changed recipient cannot be opened from the old reminder', () async {
    var launches = 0;
    final service = WhatsAppService(
      openUrl: (_) async {
        launches++;
        return true;
      },
    );
    final reminder = await pending(service);
    await service.markAsHandled(reminder);
    await DatabaseService.instance.updateCustomer(
      reminder.customer.copyWith(phone: '05000000002'),
    );
    expect(await service.openReminder(reminder), isFalse);
    expect(launches, 0);
    expect(
      (await service.checkPendingReminders()).single.customer.phone,
      '05000000002',
    );
  });

  test(
    'rescheduled appointment cannot be opened from the old reminder',
    () async {
      var launches = 0;
      final service = WhatsAppService(
        openUrl: (_) async {
          launches++;
          return true;
        },
      );
      final reminder = await pending(service);
      final moved = reminder.appointment.fullDateTime.add(
        const Duration(minutes: 5),
      );
      await DatabaseService.instance.updateAppointment(
        reminder.appointment.copyWith(
          appointmentDate: moved,
          appointmentTime:
              '${moved.hour.toString().padLeft(2, '0')}:${moved.minute.toString().padLeft(2, '0')}',
        ),
      );
      expect(await service.openReminder(reminder), isFalse);
      expect(launches, 0);
    },
  );

  test('deleted appointment cannot be opened from the old reminder', () async {
    var launches = 0;
    final service = WhatsAppService(
      openUrl: (_) async {
        launches++;
        return true;
      },
    );
    final reminder = await pending(service);
    await DatabaseService.instance.deleteAppointment(reminder.appointment.id!);
    expect(await service.openReminder(reminder), isFalse);
    expect(launches, 0);
  });

  test('edit during external launch only dismisses the opened version', () async {
    final opened = Completer<void>();
    final finish = Completer<bool>();
    final service = WhatsAppService(
      openUrl: (_) {
        opened.complete();
        return finish.future;
      },
    );
    final reminder = await pending(service);
    final opening = service.openReminder(reminder);
    await opened.future;
    final moved = reminder.appointment.fullDateTime.add(
      const Duration(minutes: 5),
    );
    await DatabaseService.instance.updateAppointment(
      reminder.appointment.copyWith(
        appointmentDate: moved,
        appointmentTime:
            '${moved.hour.toString().padLeft(2, '0')}:${moved.minute.toString().padLeft(2, '0')}',
      ),
    );
    finish.complete(true);
    expect(await opening, isTrue);
    expect(await service.checkPendingReminders(), hasLength(1));
  });
}

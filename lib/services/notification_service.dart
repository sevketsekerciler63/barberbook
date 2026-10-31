import 'dart:async';
import 'dart:io';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../services/database_service.dart';
import '../screens/alarm_screen.dart';
import '../main.dart';
import 'alarm_reconciliation.dart';
import 'alarm_scheduling.dart';
import 'serial_task_queue.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  VoidCallback? onAlarmFinished;

  StreamSubscription<AlarmSet>? _ringSubscription;
  final Set<int> _handledRingingIds = <int>{};
  final _nativeQueue = SerialTaskQueue();

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (!_isMobile) return;

    // Alarm.init() is already called in main.dart

    // Listen to the alarm ring stream
    _ringSubscription?.cancel();
    _ringSubscription = Alarm.ringing.listen((ringing) async {
      final currentIds = ringing.alarms.map((alarm) => alarm.id).toSet();
      _handledRingingIds.removeWhere((id) => !currentIds.contains(id));
      for (final alarmSettings in ringing.alarms) {
        if (_handledRingingIds.add(alarmSettings.id)) {
          await _handleAlarmRing(alarmSettings.id);
        }
      }
    });
  }

  Future<void> _handleAlarmRing(int id) async {
    debugPrint('ALARM RINGING: $id');
    final appointment = await DatabaseService.instance.getAppointmentById(id);
    if (appointment == null || !appointment.shouldHaveAlarm) {
      await cancelAlarm(id);
      return;
    }
    {
      final paymentEnabled = await DatabaseService.instance.isPaymentEnabled();
      int retries = 0;
      while (globalNavigatorKey.currentContext == null && retries < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        retries++;
      }

      if (globalNavigatorKey.currentContext != null) {
        Navigator.of(globalNavigatorKey.currentContext!).push(
          MaterialPageRoute(
            builder: (_) => AlarmScreen(
              appointment: appointment,
              paymentEnabled: paymentEnabled,
            ),
            fullscreenDialog: true,
          ),
        );
      } else {
        debugPrint(
          'Failed to push AlarmScreen: context is still null after 2 seconds.',
        );
      }
    }
  }

  /// Schedule an alarm for an appointment
  Future<AlarmScheduleResult> scheduleAlarm(Appointment appointment) async {
    if (!_isMobile) return AlarmScheduleResult.notRequired;
    return _nativeQueue.run(
      () => attemptAppointmentAlarm(
        appointment: appointment,
        now: DateTime.now(),
        schedule: (a) => _scheduleMobileAlarm(a, a.fullDateTime),
      ),
    );
  }

  Future<bool> _scheduleMobileAlarm(
    Appointment appointment,
    DateTime scheduledDate,
  ) async {
    try {
      final existing = await Alarm.getAlarms();
      final nativeTime = availableNativeAlarmTime(
        scheduledDate,
        existing
            .where((alarm) => alarm.id != appointment.id)
            .map((alarm) => alarm.dateTime),
      );
      final alarmSettings = AlarmSettings(
        id: appointment.id!,
        dateTime: nativeTime,
        assetAudioPath: 'assets/sounds/alarm.wav',
        loopAudio: true,
        vibrate: true,
        volumeSettings: const VolumeSettings.fixed(
          volume: null,
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: 'RANDEVU VAKTİ! ✂️',
          body:
              '${appointment.customerName} - ${appointment.hairstyleName ?? "Randevu"}',
        ),
        androidFullScreenIntent: true,
      );

      return await Alarm.set(alarmSettings: alarmSettings);
    } catch (e) {
      debugPrint('Error scheduling alarm: $e');
      return false;
    }
  }

  /// Strict reconciliation after restoring a database; failures reach the UI.
  Future<void> synchronizeWithAppointments() async {
    if (!_isMobile) return;
    return _nativeQueue.run(() async {
      final appointments = await DatabaseService.instance
          .getUpcomingAppointments();
      await rebuildAppointmentAlarms(
        appointments: appointments,
        now: DateTime.now(),
        cancelAll: () async {
          await Alarm.stopAll();
          _handledRingingIds.clear();
        },
        schedule: (appointment) =>
            _scheduleMobileAlarm(appointment, appointment.fullDateTime),
      );
    });
  }

  /// Cancel a scheduled alarm
  Future<void> cancelAlarm(int appointmentId) async {
    if (_isMobile) {
      await _nativeQueue.run(() async {
        try {
          await Alarm.stop(appointmentId);
        } catch (e) {
          debugPrint(
            'Warning: Failed to cancel alarm $appointmentId natively. Ignoring to prevent app crash. Error: $e',
          );
        }
      });
    }
  }

  /// Cancel all scheduled alarms
  Future<void> cancelAllAlarms() async {
    if (_isMobile) {
      await _nativeQueue.run(() async {
        try {
          await Alarm.stopAll();
        } catch (e) {
          debugPrint(
            'Warning: Failed to cancel all alarms natively. Ignoring. Error: $e',
          );
        }
      });
    }
  }

  void dispose() {
    _ringSubscription?.cancel();
  }
}

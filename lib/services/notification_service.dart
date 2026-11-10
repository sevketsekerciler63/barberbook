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
import 'alarm_delivery_gate.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  NotificationService._init();

  VoidCallback? onAlarmFinished;

  StreamSubscription<AlarmSet>? _ringSubscription;
  late final _delivery = AlarmDeliveryGate(deliver: _handleAlarmRing);
  final Set<Object> _readyOwners = {};
  final _nativeQueue = SerialTaskQueue();

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (!_isMobile) return;

    // Alarm.init() is already called by the startup gateway.

    // Listen to the alarm ring stream
    await _ringSubscription?.cancel();
    _ringSubscription = Alarm.ringing.listen((ringing) {
      final currentIds = ringing.alarms.map((alarm) => alarm.id).toSet();
      unawaited(_delivery.updateRinging(currentIds));
    });
  }

  /// Only Home can grant readiness; startup and license screens cannot display
  /// appointment details. Owners prevent an old Home disposal clearing a new one.
  void attachHome(Object owner) {
    _readyOwners.add(owner);
    unawaited(_delivery.setReady(true));
  }

  void detachHome(Object owner) {
    _readyOwners.remove(owner);
    if (_readyOwners.isEmpty) unawaited(_delivery.setReady(false));
  }

  Future<bool> _handleAlarmRing(int id, bool Function() isCurrent) async {
    debugPrint('ALARM RINGING: $id');
    if (!isCurrent()) return false;
    final revision = DatabaseService.instance.dataRevision;
    final appointment = await DatabaseService.instance.getAppointmentById(id);
    if (!isCurrent() || revision != DatabaseService.instance.dataRevision) {
      return false;
    }
    if (appointment == null || !appointment.shouldHaveAlarm) {
      await cancelAlarm(id);
      return false;
    }
    final paymentEnabled = await DatabaseService.instance.isPaymentEnabled();
    final navigator = globalNavigatorKey.currentState;
    if (!isCurrent() ||
        revision != DatabaseService.instance.dataRevision ||
        navigator == null ||
        !navigator.mounted) {
      return false;
    }
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => AlarmScreen(
            appointment: appointment,
            paymentEnabled: paymentEnabled,
          ),
          fullscreenDialog: true,
        ),
      ),
    );
    return true;
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
          _delivery.clear();
          await Alarm.stopAll();
        },
        schedule: (appointment) =>
            _scheduleMobileAlarm(appointment, appointment.fullDateTime),
      );
    });
  }

  /// Cancel a scheduled alarm
  Future<void> cancelAlarm(int appointmentId) async {
    _delivery.cancel(appointmentId);
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
    _delivery.clear();
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
    _readyOwners.clear();
    unawaited(_delivery.setReady(false));
    _delivery.clear();
    _ringSubscription?.cancel();
  }
}

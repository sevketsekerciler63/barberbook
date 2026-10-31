import 'package:flutter/material.dart';
import '../models/appointment.dart';
import '../services/notification_service.dart';

void showAppointmentAlarmWarning(
  ScaffoldMessengerState messenger,
  Appointment appointment,
) {
  if (!messenger.mounted) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 12),
      content: const Text(
        'Randevu kaydedildi, ancak alarm kurulamadı. Android alarm ve bildirim izinlerini kontrol edin.',
      ),
      action: SnackBarAction(
        label: 'Tekrar dene',
        onPressed: () async {
          // Re-read after a delay: the appointment may have been edited or cancelled.
          await NotificationService.instance
              .synchronizeWithAppointments()
              .then((_) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Planlı randevu alarmları güncellendi.'),
                    ),
                  );
                }
              })
              .catchError((Object error) {
                showAppointmentAlarmWarning(messenger, appointment);
              });
        },
      ),
    ),
  );
}

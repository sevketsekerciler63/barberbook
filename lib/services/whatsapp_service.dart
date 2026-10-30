import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../services/database_service.dart';

/// Opens prepared WhatsApp messages; it cannot verify message delivery.
class WhatsAppService {
  static final WhatsAppService instance = WhatsAppService();
  final Future<bool> Function(Uri) _openUrl;

  WhatsAppService({Future<bool> Function(Uri)? openUrl})
    : _openUrl = openUrl ?? _launchExternal;

  static Future<bool> _launchExternal(Uri uri) async {
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Keys for SharedPreferences
  static const String _keyAutoReminder = 'wp_auto_reminder';
  static const String _keyReminderMinutes = 'wp_reminder_minutes';
  static const String _keyHandledReminders = 'wp_sent_reminders';
  static const String _keyBusinessName = 'wp_business_name';
  static const String _keyCustomMessage = 'wp_custom_message';

  // Default reminder time: 60 minutes before
  static const int defaultReminderMinutes = 60;

  // Reminder interval options (in minutes)
  static const List<Map<String, dynamic>> reminderOptions = [
    {'label': '30 Dakika Önce', 'value': 30},
    {'label': '1 Saat Önce', 'value': 60},
    {'label': '2 Saat Önce', 'value': 120},
    {'label': '3 Saat Önce', 'value': 180},
    {
      'label': 'Gece Önceden (Akşam 20:00)',
      'value': -1,
    }, // special: night before
  ];

  // ==================== SETTINGS ====================

  Future<bool> isAutoReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoReminder) ?? false;
  }

  Future<void> setAutoReminderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoReminder, enabled);
  }

  Future<int> getReminderMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyReminderMinutes) ?? defaultReminderMinutes;
  }

  Future<void> setReminderMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderMinutes, minutes);
  }

  Future<String> getBusinessName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBusinessName) ?? 'BarberBook';
  }

  Future<void> setBusinessName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBusinessName, name);
  }

  Future<String> getCustomMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomMessage) ?? '';
  }

  Future<void> setCustomMessage(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomMessage, message);
  }

  // ==================== HANDLED REMINDERS ====================

  // Keep the legacy preference key so previously handled reminders stay dismissed.

  /// Track reminders opened in WhatsApp or explicitly skipped by the user.
  Future<Set<String>> _getHandledReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHandledReminders) ?? [];
    return list.toSet();
  }

  Future<void> _markReminderHandled(int appointmentId, String type) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyHandledReminders) ?? [];
    final key = '${appointmentId}_$type';
    if (!list.contains(key)) {
      list.add(key);
      await prefs.setStringList(_keyHandledReminders, list);
    }
  }

  Future<bool> _isReminderHandled(int appointmentId, String type) async {
    final sent = await _getHandledReminders();
    return sent.contains('${appointmentId}_$type');
  }

  /// Clean up old sent reminders (older than 7 days)
  Future<void> cleanupOldReminders() async {
    final prefs = await SharedPreferences.getInstance();
    // Simple cleanup: just clear the list periodically if it gets too big
    final list = prefs.getStringList(_keyHandledReminders) ?? [];
    if (list.length > 500) {
      // Keep only last 100
      final trimmed = list.sublist(list.length - 100);
      await prefs.setStringList(_keyHandledReminders, trimmed);
    }
  }

  // ==================== MESSAGE GENERATION ====================

  /// Generate the WhatsApp reminder message for an appointment
  Future<String> generateReminderMessage(Appointment appointment) async {
    final businessName = await getBusinessName();
    final customMsg = await getCustomMessage();

    final date =
        '${appointment.appointmentDate.day.toString().padLeft(2, '0')}/'
        '${appointment.appointmentDate.month.toString().padLeft(2, '0')}/'
        '${appointment.appointmentDate.year}';

    final time = appointment.appointmentTime;
    final hairstyle = appointment.hairstyleName ?? '';

    String message =
        'Merhaba ${appointment.customerName} 👋\n\n'
        '📅 *$date* tarihinde saat *$time* için randevunuz bulunmaktadır.\n';

    if (hairstyle.isNotEmpty) {
      message += '✂️ İşlem: *$hairstyle*\n';
    }

    message += '\n🏠 *$businessName*\n';

    if (customMsg.isNotEmpty) {
      message += '\n$customMsg\n';
    }

    message += '\nSizi bekliyoruz! 😊';

    return message;
  }

  /// Generate a custom message with replaceable placeholders
  String generateCustomMessage({
    required String template,
    required Appointment appointment,
    required String businessName,
  }) {
    final date =
        '${appointment.appointmentDate.day.toString().padLeft(2, '0')}/'
        '${appointment.appointmentDate.month.toString().padLeft(2, '0')}/'
        '${appointment.appointmentDate.year}';

    return template
        .replaceAll('{isim}', appointment.customerName)
        .replaceAll('{tarih}', date)
        .replaceAll('{saat}', appointment.appointmentTime)
        .replaceAll('{islem}', appointment.hairstyleName ?? 'Belirtilmedi')
        .replaceAll('{dukkan}', businessName);
  }

  // ==================== WHATSAPP ACTIONS ====================

  /// Format phone number for WhatsApp (Turkey country code)
  String _formatPhoneForWhatsApp(String phone) {
    // Telefon numarasındaki tüm rakam dışı karakterleri temizle
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    // Başında '0' varsa Türkiye kodu 90 ekle
    if (cleaned.startsWith('0')) {
      cleaned = '90${cleaned.substring(1)}';
    }
    // 10 haneli ve 90 ile başlamıyorsa başına 90 ekle
    else if (!cleaned.startsWith('90') && cleaned.length == 10) {
      cleaned = '90$cleaned';
    }

    return cleaned;
  }

  /// Open WhatsApp with a pre-filled message for a specific appointment
  Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final formattedPhone = _formatPhoneForWhatsApp(phone);
    final encodedMessage = Uri.encodeComponent(message);

    // Try WhatsApp deep link first (works better on mobile)
    final whatsappUrl = Uri.parse(
      'https://wa.me/$formattedPhone?text=$encodedMessage',
    );

    try {
      return await _openUrl(whatsappUrl);
    } catch (e) {
      debugPrint('WhatsApp başlatma hatası: $e');
    }

    return false;
  }

  /// Send a reminder for a specific appointment
  Future<bool> sendAppointmentReminder(Appointment appointment) async {
    if (appointment.customerId == null) return false;

    final customer = await DatabaseService.instance.getCustomerById(
      appointment.customerId!,
    );
    if (customer == null || customer.phone == null || customer.phone!.isEmpty) {
      return false;
    }

    final message = await generateReminderMessage(appointment);
    return sendWhatsAppMessage(phone: customer.phone!, message: message);
  }

  // ==================== AUTO REMINDER CHECK ====================

  /// Check all upcoming appointments and determine which ones need reminders.
  /// Returns a list of appointments that should receive a reminder NOW.
  Future<List<AppointmentReminder>> checkPendingReminders() async {
    final isEnabled = await isAutoReminderEnabled();
    if (!isEnabled) return [];

    final reminderMinutes = await getReminderMinutes();
    final now = DateTime.now();
    final db = DatabaseService.instance;
    final upcoming = await db.getUpcomingAppointments();

    final List<AppointmentReminder> pendingReminders = [];

    for (final appointment in upcoming) {
      if (appointment.id == null || appointment.customerId == null) continue;
      if (appointment.isCompleted) continue;

      final customer = await db.getCustomerById(appointment.customerId!);
      if (customer == null ||
          customer.phone == null ||
          customer.phone!.isEmpty) {
        continue;
      }

      final appointmentDateTime = appointment.fullDateTime;
      final reminderType = reminderMinutes == -1
          ? 'auto_night_before'
          : 'auto_${reminderMinutes}m';

      // Check if already sent
      if (await _isReminderHandled(appointment.id!, reminderType)) continue;

      bool shouldSend = false;

      if (reminderMinutes == -1) {
        // "Night before" mode: Send at 20:00 the day before
        final nightBefore = DateTime(
          appointmentDateTime.year,
          appointmentDateTime.month,
          appointmentDateTime.day - 1,
          20,
          0,
        );
        // Send if we're past 20:00 the night before but before the appointment
        shouldSend =
            now.isAfter(nightBefore) && now.isBefore(appointmentDateTime);
      } else {
        // Standard: send X minutes before
        final reminderTime = appointmentDateTime.subtract(
          Duration(minutes: reminderMinutes),
        );
        // Send if we're in the reminder window (between reminder time and appointment time)
        shouldSend =
            now.isAfter(reminderTime) && now.isBefore(appointmentDateTime);
      }

      if (shouldSend) {
        final message = await generateReminderMessage(appointment);
        pendingReminders.add(
          AppointmentReminder(
            appointment: appointment,
            customer: customer,
            message: message,
            reminderType: reminderType,
          ),
        );
      }
    }

    return pendingReminders;
  }

  /// Open a reminder and dismiss it only if the external app launch succeeded.
  /// Success means the prepared message was opened, never that it was sent.
  Future<bool> openReminder(AppointmentReminder reminder) async {
    final phone = reminder.customer.phone;
    final id = reminder.appointment.id;
    if (id == null || phone == null || phone.trim().isEmpty) return false;
    final opened = await sendWhatsAppMessage(
      phone: phone,
      message: reminder.message,
    );
    if (opened) await markAsHandled(id, reminder.reminderType);
    return opened;
  }

  /// Dismiss a reminder after opening or explicitly skipping it.
  Future<void> markAsHandled(int appointmentId, String reminderType) async {
    await _markReminderHandled(appointmentId, reminderType);
  }
}

/// Data class for a pending appointment reminder
class AppointmentReminder {
  final Appointment appointment;
  final Customer customer;
  final String message;
  final String reminderType;

  AppointmentReminder({
    required this.appointment,
    required this.customer,
    required this.message,
    required this.reminderType,
  });
}

import '../services/latest_request.dart';
import '../services/alarm_scheduling.dart';
import '../widgets/alarm_feedback.dart';
import '../services/customer_phone_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/appointment.dart';
import '../models/payment.dart';
import '../models/payment_transaction.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/constants.dart';
import '../widgets/appointment_card.dart';
import '../widgets/home_header.dart';
import 'add_appointment_screen.dart';
import 'customers_screen.dart';
import 'whatsapp_settings_screen.dart';
import 'service_management_screen.dart';
import 'working_hours_screen.dart';
import 'backup_screen.dart';
import 'payment_dialog.dart';
import 'cash_report_screen.dart';
import 'receivables_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _dbService = DatabaseService.instance;
  final _dateRequest = LatestRequest();
  final _searchRequest = LatestRequest();
  String? _loadError;
  String? _searchError;
  DateTime _selectedDate = DateTime.now();
  List<Appointment> _appointments = [];
  PaymentSummary _paymentSummary = PaymentSummary.fromPayments(const []);
  bool _paymentEnabled = true;
  bool _isLoading = true;
  bool _showCalendar = false;

  final TextEditingController _searchController = TextEditingController();
  List<Appointment> _searchResults = [];
  bool _isSearching = false;

  final Map<int, String> _customerPhones = {};
  final Map<int, String> _searchCustomerPhones = {};

  Timer? _whatsappReminderTimer;
  bool _reminderDialogOpen = false;
  bool _openingWhatsAppReminder = false;

  @override
  void initState() {
    super.initState();
    _loadAppointments();
    NotificationService.instance.onAlarmFinished = _loadAppointments;
    _checkRequiredPermissions();
    _startWhatsAppReminderChecker();
  }

  Future<void> _checkRequiredPermissions() async {
    if (Platform.isIOS) {
      final isNotificationGranted = await Permission.notification.isGranted;
      if (!isNotificationGranted) {
        await Permission.notification.request();
      }
      return;
    }

    if (!Platform.isAndroid) return;

    try {
      final isNotificationGranted = await Permission.notification.isGranted;
      final isExactAlarmGranted = await Permission.scheduleExactAlarm.isGranted;
      final isBatteryGranted =
          await Permission.ignoreBatteryOptimizations.isGranted;
      final isSystemAlertGranted = await Permission.systemAlertWindow.isGranted;

      if (!isNotificationGranted ||
          !isExactAlarmGranted ||
          !isBatteryGranted ||
          !isSystemAlertGranted) {
        if (!mounted) return;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.gold,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text(
                  'Önemli İzinler',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Text(
                'Ekran kilitliyken veya uygulama arka plandayken randevu alarmı ve bildirim gösterebilmek için Android izinlerini düzenleyin. Telefonun güç yönetimi alarm davranışını etkileyebilir:\n\n'
                '1. Bildirim ve tam zamanlı alarm izinleri.\n'
                '2. Arka plan kısıtlamalarını azaltmak için pil optimizasyonu ayarı.\n'
                '3. Alarm ekranı için diğer uygulamalar üzerinde gösterme izni.\n\n'
                'Ayarları yaptıktan sonra kendi telefonunuzda bir deneme alarmı kurun.',
                style: TextStyle(
                  color: AppColors.white,
                  height: 1.5,
                  fontSize: 15,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Daha Sonra',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  if (!isNotificationGranted) {
                    await Permission.notification.request();
                  }
                  if (!isExactAlarmGranted) {
                    await Permission.scheduleExactAlarm.request();
                  }
                  if (!isBatteryGranted) {
                    await Permission.ignoreBatteryOptimizations.request();
                  }
                  if (!isSystemAlertGranted) {
                    await Permission.systemAlertWindow.request();
                  }
                },
                child: const Text(
                  'Anladım, İzin Ver',
                  style: TextStyle(
                    color: AppColors.background,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
    }
  }

  @override
  void dispose() {
    _dateRequest.dispose();
    _searchRequest.dispose();
    if (NotificationService.instance.onAlarmFinished == _loadAppointments) {
      NotificationService.instance.onAlarmFinished = null;
    }
    _searchController.dispose();
    _whatsappReminderTimer?.cancel();
    super.dispose();
  }

  // ==================== WHATSAPP REMINDER ====================

  void _startWhatsAppReminderChecker() {
    // Check every 60 seconds for pending WhatsApp reminders
    _whatsappReminderTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkWhatsAppReminders();
    });
    // Also check immediately after a short delay
    Future.delayed(const Duration(seconds: 5), _checkWhatsAppReminders);
  }

  Future<void> _checkWhatsAppReminders() async {
    if (!mounted ||
        _reminderDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    try {
      final pendingReminders = await WhatsAppService.instance
          .checkPendingReminders();
      if (pendingReminders.isEmpty) return;
      if (!mounted ||
          _reminderDialogOpen ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      // Show reminder dialog for the first pending one
      final reminder = pendingReminders.first;
      _reminderDialogOpen = true;
      try {
        await _showWhatsAppReminderDialog(reminder);
      } finally {
        _reminderDialogOpen = false;
      }
    } catch (e) {
      debugPrint('WhatsApp reminder check error: $e');
    }
  }

  Future<void> _showWhatsAppReminderDialog(AppointmentReminder reminder) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.chat, color: Color(0xFF25D366), size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'WhatsApp Hatırlatma',
                style: TextStyle(
                  color: Color(0xFF25D366),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${reminder.appointment.customerName} kişisinin randevusu yaklaşıyor!',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '📅 ${reminder.appointment.appointmentDate.day.toString().padLeft(2, '0')}/${reminder.appointment.appointmentDate.month.toString().padLeft(2, '0')} - ⏰ ${reminder.appointment.appointmentTime}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '📱 ${reminder.customer.phone}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                reminder.message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Skip this reminder
              await WhatsAppService.instance.markAsHandled(reminder);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Atla',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.send, color: Colors.white, size: 18),
            label: const Text(
              'WhatsApp’ta aç',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () async {
              if (_openingWhatsAppReminder) return;
              _openingWhatsAppReminder = true;
              try {
                final opened = await WhatsAppService.instance.openReminder(
                  reminder,
                );
                if (!context.mounted) return;
                if (opened) {
                  Navigator.pop(context);
                } else {
                  _showSnackBar(
                    'WhatsApp açılamadı veya randevu bilgisi değişti. Listeyi yenileyip tekrar deneyin.',
                  );
                }
              } finally {
                _openingWhatsAppReminder = false;
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendWhatsAppForAppointment(Appointment appointment) async {
    if (appointment.customerId == null) {
      _showSnackBar('Bu müşterinin bilgisi kayıtlı değil.');
      return;
    }

    final customer = await _dbService.getCustomerById(appointment.customerId!);
    if (customer == null || customer.phone == null || customer.phone!.isEmpty) {
      _showSnackBar('Bu müşterinin telefon numarası kayıtlı değil.');
      return;
    }

    final message = await WhatsAppService.instance.generateReminderMessage(
      appointment,
    );
    final sent = await WhatsAppService.instance.sendWhatsAppMessage(
      phone: customer.phone!,
      message: message,
    );

    if (!sent && mounted) {
      _showSnackBar(
        'WhatsApp açılamadı. Lütfen WhatsApp yüklü olduğundan emin olun.',
      );
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: AppColors.white)),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _loadAppointments() async {
    if (!mounted) return;
    final date = _selectedDate;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    await _dateRequest.run(
      load: () async {
        final settings = await Future.wait([
          _dbService.getAppointmentsByDate(date),
          _dbService.getPaymentsForDate(date),
          _dbService.getPaymentTransactionsForDate(date),
          _dbService.isPaymentEnabled(),
        ]);
        final appointments = settings[0] as List<Appointment>;
        final payments = settings[1] as List<Payment>;
        final transactions = settings[2] as List<PaymentTransaction>;
        final paymentEnabled = settings[3] as bool;
        final collectionPayments = transactions
            .where((item) => item.type == PaymentTransactionType.collection)
            .map(
              (item) => Payment(
                appointmentId: item.appointmentId,
                amountCents: item.amountCents,
                status: PaymentStatus.paid,
                method: item.method,
                paidAt: item.occurredAt,
                note: item.note,
                createdAt: item.createdAt,
              ),
            );

        final phones = await CustomerPhoneService.load(appointments);

        appointments.sort((a, b) {
          if (a.isCompleted == b.isCompleted) {
            return a.appointmentTime.compareTo(b.appointmentTime);
          }
          return a.isCompleted ? 1 : -1;
        });

        return (
          appointments: appointments,
          payments: [...payments, ...collectionPayments],
          phones: phones,
          paymentEnabled: paymentEnabled,
        );
      },
      apply: (data) {
        if (!mounted) return;
        setState(() {
          _appointments = data.appointments;
          _paymentSummary = PaymentSummary.fromPayments(data.payments);
          _paymentEnabled = data.paymentEnabled;
          _customerPhones
            ..clear()
            ..addAll(data.phones);
          _isLoading = false;
        });
      },
      onError: (_, _) {
        if (!mounted) return;
        setState(() {
          _appointments = [];
          _isLoading = false;
          _loadError = 'Randevular yüklenemedi. Tekrar deneyin.';
        });
      },
    );
  }

  Future<void> _runAppointmentAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _showSnackBar(
          'İşlem kaydedilemedi. Güncel kayıtları kontrol edip tekrar deneyin.',
        );
        await _loadAppointments();
      }
    }
  }

  Future<void> _changeAppointmentStatus(Appointment appointment) async {
    if (appointment.id == null) return;

    final selected = await showModalBottomSheet<AppointmentStatus>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Randevu durumu',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _statusOption(
              AppointmentStatus.planned,
              'Planlandı',
              Icons.event_available,
            ),
            _statusOption(
              AppointmentStatus.completed,
              'Tamamlandı',
              Icons.check_circle,
            ),
            _statusOption(
              AppointmentStatus.cancelled,
              'İptal edildi',
              Icons.event_busy,
            ),
            _statusOption(
              AppointmentStatus.noShow,
              'Gelmedi',
              Icons.person_off,
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    if (selected == AppointmentStatus.completed && _paymentEnabled) {
      final existing = await _dbService.getPaymentForAppointment(
        appointment.id!,
      );
      if (existing != null && existing.status != PaymentStatus.unknown) {
        // Status changes never replace an existing financial record.
        await _dbService.completeAppointmentWithoutPayment(appointment.id!);
      } else {
        if (!mounted) return;
        final payment = await showPaymentDialog(
          context,
          appointment,
          existing: existing,
        );
        if (payment == null) {
          if (mounted) await _loadAppointments();
          return;
        }
        await _dbService.completeAppointmentWithPayment(
          appointment.id!,
          payment,
        );
      }
    } else if (selected == AppointmentStatus.completed) {
      await _dbService.completeAppointmentWithoutPayment(appointment.id!);
    } else {
      await _dbService.setAppointmentStatus(appointment.id!, selected);
    }
    await NotificationService.instance.cancelAlarm(appointment.id!);
    final updatedAppointment = appointment.copyWith(status: selected);
    if (updatedAppointment.shouldHaveAlarm &&
        updatedAppointment.fullDateTime.isAfter(DateTime.now())) {
      final alarmResult = await NotificationService.instance.scheduleAlarm(
        updatedAppointment,
      );
      if (mounted && alarmResult == AlarmScheduleResult.failed) {
        showAppointmentAlarmWarning(
          ScaffoldMessenger.of(context),
          updatedAppointment,
        );
      }
    }
    await _loadAppointments();
    if (_isSearching) await _searchAppointments(_searchController.text);
  }

  Widget _statusOption(AppointmentStatus status, String label, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppColors.gold),
      title: Text(label, style: const TextStyle(color: AppColors.white)),
      onTap: () => Navigator.pop(context, status),
    );
  }

  Future<void> _callAppointmentCustomer(Appointment appointment) async {
    if (appointment.customerId == null) return;
    final customer = await _dbService.getCustomerById(appointment.customerId!);
    if (customer != null &&
        customer.phone != null &&
        customer.phone!.isNotEmpty) {
      final uri = Uri.parse('tel:${customer.phone}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Bu müşterinin telefon numarası kayıtlı değil.',
              style: TextStyle(color: AppColors.white),
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleAppointmentCompletion(Appointment appointment) async {
    if (appointment.id == null) return;

    final newStatus = !appointment.isCompleted;
    if (newStatus && _paymentEnabled) {
      final existing = await _dbService.getPaymentForAppointment(
        appointment.id!,
      );
      if (existing != null && existing.status != PaymentStatus.unknown) {
        // Status changes never replace an existing financial record.
        await _dbService.completeAppointmentWithoutPayment(appointment.id!);
      } else {
        if (!mounted) return;
        final payment = await showPaymentDialog(
          context,
          appointment,
          existing: existing,
        );
        if (payment == null) {
          if (mounted) await _loadAppointments();
          return;
        }
        await _dbService.completeAppointmentWithPayment(
          appointment.id!,
          payment,
        );
      }
    } else if (newStatus) {
      await _dbService.completeAppointmentWithoutPayment(appointment.id!);
    } else {
      await _dbService.toggleAppointmentCompletion(appointment.id!, false);
    }

    if (newStatus) {
      await NotificationService.instance.cancelAlarm(appointment.id!);
    } else {
      // Reschedule the alarm if we are un-completing it and it's in the future
      final updatedAppt = appointment.copyWith(isCompleted: false);
      if (updatedAppt.fullDateTime.isAfter(DateTime.now())) {
        final alarmResult = await NotificationService.instance.scheduleAlarm(
          updatedAppt,
        );
        if (mounted && alarmResult == AlarmScheduleResult.failed) {
          showAppointmentAlarmWarning(
            ScaffoldMessenger.of(context),
            updatedAppt,
          );
        }
      }
    }
    await _loadAppointments();
    if (_isSearching) {
      await _searchAppointments(_searchController.text);
    }
  }

  void _goToDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _showCalendar = false;
    });
    _loadAppointments();
  }

  Future<void> _searchAppointments(String query) async {
    if (!mounted) return;
    if (query.trim().isEmpty) {
      _searchRequest.invalidate();
      setState(() {
        _searchResults = [];
        _searchCustomerPhones.clear();
        _searchError = null;
      });
      return;
    }
    setState(() => _searchError = null);
    await _searchRequest.run(
      load: () async {
        final results = await _dbService.searchAppointments(query);
        final phones = await CustomerPhoneService.load(results);
        return (results: results, phones: phones);
      },
      apply: (data) {
        if (mounted) {
          setState(() {
            _searchResults = data.results;
            _searchCustomerPhones
              ..clear()
              ..addAll(data.phones);
          });
        }
      },
      onError: (_, _) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _searchError = 'Arama yapılamadı. Tekrar deneyin.';
          });
        }
      },
    );
  }

  void _goToToday() {
    _goToDate(DateTime.now());
  }

  void _previousDay() {
    final newDate = _selectedDate.subtract(const Duration(days: 1));
    _goToDate(newDate);
  }

  void _nextDay() {
    _goToDate(_selectedDate.add(const Duration(days: 1)));
  }

  Future<void> _addAppointment() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddAppointmentScreen(initialDate: _selectedDate),
      ),
    );
    if (result == true) {
      await _loadAppointments();
      if (_isSearching) {
        await _searchAppointments(_searchController.text);
      }
    }
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Appointment? get _nextCustomerToday {
    if (!_isToday) return null;
    final now = DateTime.now();
    for (final appointment in _appointments) {
      if (appointment.isActive && appointment.fullDateTime.isAfter(now)) {
        return appointment;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');
    final completedCount = _appointments.where((a) => a.isCompleted).length;
    final totalCount = _appointments.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            HomeHeader(
              managementMenu: PopupMenuButton<String>(
                icon: const Icon(Icons.settings, color: AppColors.gold),
                tooltip: 'Yönetim',
                color: AppColors.surface,
                onSelected: (value) async {
                  final Widget screen = switch (value) {
                    'services' => const ServiceManagementScreen(),
                    'hours' => const WorkingHoursScreen(),
                    'cash_report' => const CashReportScreen(),
                    'receivables' => const ReceivablesScreen(),
                    'backup' => const BackupScreen(),
                    _ => const WhatsAppSettingsScreen(),
                  };
                  final changed = await Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => screen));
                  if (mounted &&
                      ((value == 'backup' && changed == true) ||
                          value == 'receivables' ||
                          value == 'cash_report')) {
                    await _loadAppointments();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'services',
                    child: Text('Hizmetler'),
                  ),
                  const PopupMenuItem(
                    value: 'hours',
                    child: Text('Çalışma saatleri'),
                  ),
                  if (_paymentEnabled)
                    const PopupMenuItem(
                      value: 'cash_report',
                      child: Text('Tahsilat raporu'),
                    ),
                  if (_paymentEnabled)
                    const PopupMenuItem(
                      value: 'receivables',
                      child: Text('Açık veresiyeler'),
                    ),
                  const PopupMenuItem(
                    value: 'backup',
                    child: Text('Yedekleme'),
                  ),
                  const PopupMenuItem(
                    value: 'whatsapp',
                    child: Text('WhatsApp ayarları'),
                  ),
                ],
              ),
              isSearching: _isSearching,
              onSearchPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchRequest.invalidate();
                    _searchController.clear();
                    _searchResults.clear();
                    _searchCustomerPhones.clear();
                  }
                });
              },
              showTodayButton: !_isToday,
              onTodayPressed: _goToToday,
            ),

            const SizedBox(height: 16),

            if (_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchAppointments,
                    style: const TextStyle(color: AppColors.white),
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      hintText: 'Müşterilerde Ara...',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.textSecondary,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),

            // Date navigation
            if (!_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _previousDay,
                      icon: const Icon(
                        Icons.chevron_left,
                        color: AppColors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _showCalendar = !_showCalendar),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Text(
                                dateFormat.format(_selectedDate),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _isToday
                                      ? AppColors.gold
                                      : AppColors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (totalCount > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '$completedCount/$totalCount tamamlandı',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _nextDay,
                      icon: const Icon(
                        Icons.chevron_right,
                        color: AppColors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                      ),
                    ),
                  ],
                ),
              ),

            // Calendar (expandable)
            if (!_isSearching && _showCalendar)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TableCalendar(
                  firstDay: DateTime.now().subtract(const Duration(days: 1800)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _selectedDate,
                  selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
                  onDaySelected: (selectedDay, focusedDay) {
                    _goToDate(selectedDay);
                  },
                  locale: 'tr_TR',
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    leftChevronIcon: Icon(
                      Icons.chevron_left,
                      color: AppColors.gold,
                    ),
                    rightChevronIcon: Icon(
                      Icons.chevron_right,
                      color: AppColors.gold,
                    ),
                  ),
                  calendarStyle: CalendarStyle(
                    defaultTextStyle: const TextStyle(color: AppColors.white),
                    weekendTextStyle: const TextStyle(color: AppColors.white),
                    outsideTextStyle: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                    todayDecoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(color: AppColors.gold),
                    selectedDecoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                    selectedTextStyle: const TextStyle(
                      color: AppColors.background,
                    ),
                  ),
                  daysOfWeekStyle: const DaysOfWeekStyle(
                    weekdayStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    weekendStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

            if (!_isSearching && _nextCustomerToday != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_pin_circle, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sıradaki: ${_nextCustomerToday!.customerName} • ${_nextCustomerToday!.appointmentTime}',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_paymentEnabled &&
                !_isSearching &&
                _paymentSummary.collectedCents > 0)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments, color: AppColors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bugünkü tahsilat: ${(_paymentSummary.collectedCents / 100).toStringAsFixed(2)} ₺',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            // Appointments list
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.gold),
                    )
                  : (_isSearching && _searchController.text.trim().isEmpty)
                  ? const Center(
                      child: Text(
                        'Aramak istediğiniz ismi yazın',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                      ),
                    )
                  : (_isSearching ? _searchResults : _appointments).isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isSearching
                                ? Icons.search_off
                                : Icons.event_available,
                            size: 64,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isSearching
                                ? (_searchError ?? 'Arama sonucu bulunamadı')
                                : (_loadError ??
                                      (_isToday
                                          ? 'Bugün randevu yok'
                                          : 'Bu gün için randevu yok')),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                          if (!_isSearching) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _loadError == null
                                  ? _addAppointment
                                  : _loadAppointments,
                              icon: const Icon(
                                Icons.add,
                                color: AppColors.gold,
                              ),
                              label: Text(
                                _loadError == null
                                    ? 'Randevu Ekle'
                                    : 'Tekrar dene',
                                style: const TextStyle(color: AppColors.gold),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 100),
                      itemCount: _isSearching
                          ? _searchResults.length
                          : _appointments.length,
                      itemBuilder: (context, index) {
                        final appointment = _isSearching
                            ? _searchResults[index]
                            : _appointments[index];
                        return Slidable(
                          key: ValueKey(appointment.id),
                          endActionPane: ActionPane(
                            motion: const BehindMotion(),
                            extentRatio: 0.5,
                            children: [
                              SlidableAction(
                                onPressed: (_) async {
                                  final result = await Navigator.of(context)
                                      .push<bool>(
                                        MaterialPageRoute(
                                          builder: (_) => AddAppointmentScreen(
                                            initialDate:
                                                appointment.appointmentDate,
                                            appointmentToEdit: appointment,
                                          ),
                                        ),
                                      );
                                  if (result == true) {
                                    await _loadAppointments();
                                    if (_isSearching) {
                                      await _searchAppointments(
                                        _searchController.text,
                                      );
                                    }
                                  }
                                },
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.background,
                                icon: Icons.edit,
                                label: 'Düzenle',
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(14),
                                  bottomLeft: Radius.circular(14),
                                ),
                              ),
                              SlidableAction(
                                onPressed: (_) => _runAppointmentAction(
                                  () => _changeAppointmentStatus(appointment),
                                ),
                                backgroundColor: AppColors.red,
                                foregroundColor: Colors.white,
                                icon: Icons.event_busy,
                                label: 'Durum',
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(14),
                                  bottomRight: Radius.circular(14),
                                ),
                              ),
                            ],
                          ),
                          child: AppointmentCard(
                            appointment: appointment,
                            onComplete: () => _runAppointmentAction(
                              () => _toggleAppointmentCompletion(appointment),
                            ),
                            showDate: _isSearching,
                            customerPhone: appointment.customerId != null
                                ? (_isSearching
                                      ? _searchCustomerPhones
                                      : _customerPhones)[appointment
                                      .customerId!]
                                : null,
                            onCall: appointment.customerId != null
                                ? () => _callAppointmentCustomer(appointment)
                                : null,
                            onWhatsApp: appointment.customerId != null
                                ? () => _sendWhatsAppForAppointment(appointment)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),

      // Bottom navigation
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // Customers button
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomersScreen(),
                        ),
                      );
                      _loadAppointments();
                      if (_isSearching && _searchController.text.isNotEmpty) {
                        _searchAppointments(_searchController.text);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people, color: AppColors.white, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Müşteriler',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Add appointment button
                Expanded(
                  child: GestureDetector(
                    onTap: _addAppointment,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add,
                            color: AppColors.background,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Randevu',
                            style: TextStyle(
                              color: AppColors.background,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

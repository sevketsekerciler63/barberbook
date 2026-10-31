import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment.dart';
import '../models/payment.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import 'payment_dialog.dart';

class AlarmScreen extends StatefulWidget {
  final Appointment appointment;
  final bool paymentEnabled;

  const AlarmScreen({
    super.key,
    required this.appointment,
    this.paymentEnabled = true,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _bellController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _bellAnimation;
  String? _customerPhone;
  bool _acknowledged = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCustomer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..repeat(reverse: true);
    _bellAnimation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(parent: _bellController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bellController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    if (widget.appointment.customerId == null) return;
    final customer = await DatabaseService.instance.getCustomerById(
      widget.appointment.customerId!,
    );
    if (customer?.phone != null && mounted) {
      setState(() => _customerPhone = customer!.phone);
    }
  }

  Future<void> _acknowledge() async {
    if (_acknowledged) return;
    if (widget.appointment.id != null) {
      await NotificationService.instance.cancelAlarm(widget.appointment.id!);
    }
    if (!mounted) return;
    setState(() => _acknowledged = true);
    _pulseController.stop();
    _bellController.stop();
  }

  Future<void> _closeAlarm() async {
    await _acknowledge();
    NotificationService.instance.onAlarmFinished?.call();
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _complete({Payment? payment}) async {
    final id = widget.appointment.id;
    if (id == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _acknowledge();
      if (payment == null) {
        await DatabaseService.instance.completeAppointmentWithoutPayment(id);
      } else {
        await DatabaseService.instance.completeAppointmentWithPayment(
          id,
          payment,
        );
      }
      NotificationService.instance.onAlarmFinished?.call();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'İşlem kaydedilemedi. Kayıtlı ödeme korunuyor; yeniden deneyin.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _takePayment() async {
    await _acknowledge();
    if (!mounted) return;
    final existing = widget.appointment.id == null
        ? null
        : await DatabaseService.instance.getPaymentForAppointment(
            widget.appointment.id!,
          );
    if (!mounted) return;
    final payment = await showPaymentDialog(
      context,
      widget.appointment,
      existing: existing,
    );
    if (payment != null) await _complete(payment: payment);
  }

  Future<void> _callCustomer() async {
    await _acknowledge();
    if (_customerPhone == null) return;
    try {
      await launchUrl(Uri.parse('tel:$_customerPhone'));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) => Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.5,
                colors: [
                  AppColors.red.withValues(
                    alpha: _acknowledged ? 0.08 : _pulseAnimation.value,
                  ),
                  AppColors.background,
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _bellAnimation,
                      builder: (context, child) => Transform.rotate(
                        angle: _acknowledged ? 0 : _bellAnimation.value,
                        child: Icon(
                          _acknowledged
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_active,
                          color: AppColors.gold,
                          size: 80,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _acknowledged ? 'ALARM KAPATILDI' : 'RANDEVU VAKTİ!',
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.appointment.appointmentTime,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.appointment.customerName,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.appointment.hairstyleName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.appointment.hairstyleName!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 18,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (_customerPhone != null)
                      OutlinedButton.icon(
                        onPressed: _callCustomer,
                        icon: const Icon(Icons.phone),
                        label: const Text('Ara'),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _closeAlarm,
                            icon: const Icon(Icons.close),
                            label: const Text('Kapat'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saving ? null : () => _complete(),
                            icon: const Icon(Icons.check),
                            label: const Text('Tamamlandı'),
                          ),
                        ),
                      ],
                    ),
                    if (widget.paymentEnabled) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _saving ? null : _takePayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Ödeme al'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

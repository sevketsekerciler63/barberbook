import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../models/barber_service.dart';
import '../models/working_schedule.dart';
import '../services/database_service.dart';
import '../services/appointment_customer_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../utils/hairstyle_data.dart';
import '../widgets/customer_search.dart';
import 'hairstyle_gallery.dart';

class AddAppointmentScreen extends StatefulWidget {
  final DateTime? initialDate;
  final Appointment? appointmentToEdit;
  final Appointment? appointmentToRepeat;

  const AddAppointmentScreen({
    super.key,
    this.initialDate,
    this.appointmentToEdit,
    this.appointmentToRepeat,
  });

  @override
  State<AddAppointmentScreen> createState() => _AddAppointmentScreenState();
}

class _AddAppointmentScreenState extends State<AddAppointmentScreen> {
  final _notesController = TextEditingController();
  final _phoneController = TextEditingController();

  late DateTime _selectedDate;
  TimeOfDay? _selectedTime;
  Customer? _selectedCustomer;
  bool _isSaving = false;
  bool _saveCompleted = false;
  String _customerName = '';
  HairstyleModel? _selectedHairstyle;
  List<BarberService> _services = [];
  BarberService? _selectedService;

  final _dbService = DatabaseService.instance;

  bool get _isRepeating => widget.appointmentToRepeat != null;

  @override
  void initState() {
    super.initState();
    final source = widget.appointmentToEdit ?? widget.appointmentToRepeat;
    if (source != null) {
      final apt = source;
      _selectedDate =
          widget.appointmentToEdit?.appointmentDate ??
          widget.initialDate ??
          DateTime.now();
      if (widget.appointmentToEdit != null) {
        final parts = apt.appointmentTime.split(':');
        _selectedTime = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
      _customerName = apt.customerName;
      _notesController.text = apt.notes ?? '';
      if (apt.hairstyleId != null && apt.hairstyleName != null) {
        _selectedHairstyle = HairstyleModel(
          id: apt.hairstyleId!,
          name: apt.hairstyleName!,
          imagePath: '',
        );
      }
      if (apt.customerId != null) {
        _loadCustomerToEdit(apt.customerId!);
      }
    } else {
      _selectedDate = widget.initialDate ?? DateTime.now();
    }
    _loadServices();
  }

  Future<void> _loadServices() async {
    final allServices = await _dbService.getServices(activeOnly: false);
    final selected = selectServiceForAppointment(
      allServices,
      widget.appointmentToEdit?.serviceId ??
          widget.appointmentToRepeat?.serviceId,
    );
    final visibleServices = widget.appointmentToEdit == null && !_isRepeating
        ? allServices.where((service) => service.isActive).toList()
        : allServices
              .where(
                (service) => service.isActive || service.id == selected?.id,
              )
              .toList();
    if (!mounted) return;
    setState(() {
      _services = visibleServices;
      _selectedService = selected;
    });
  }

  Future<void> _loadCustomerToEdit(int id) async {
    final c = await _dbService.getCustomerById(id);
    if (c != null && mounted) {
      setState(() {
        _selectedCustomer = c;
        _phoneController.text = c.phone ?? '';
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedDate = DateUtils.dateOnly(_selectedDate);
    final earliest = today.subtract(const Duration(days: 1));
    final latest = today.add(const Duration(days: 365));
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: selectedDate.isBefore(earliest) ? selectedDate : earliest,
      lastDate: selectedDate.isAfter(latest) ? selectedDate : latest,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.gold,
              onPrimary: AppColors.background,
              surface: AppColors.surface,
              onSurface: AppColors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final initialDateTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      _selectedTime?.hour ?? DateTime.now().hour,
      _selectedTime?.minute ?? DateTime.now().minute,
    );

    DateTime? tempPickedDate;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext builder) {
        return Container(
          height: 300,
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'İptal',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const Text(
                      'Saat Seç',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (tempPickedDate != null) {
                          setState(() {
                            _selectedTime = TimeOfDay(
                              hour: tempPickedDate!.hour,
                              minute: tempPickedDate!.minute,
                            );
                          });
                        } else if (_selectedTime == null) {
                          setState(() {
                            _selectedTime = TimeOfDay(
                              hour: initialDateTime.hour,
                              minute: initialDateTime.minute,
                            );
                          });
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Bitti',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.dark,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: AppColors.white,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    use24hFormat: true,
                    initialDateTime: initialDateTime,
                    onDateTimeChanged: (DateTime newDateTime) {
                      tempPickedDate = newDateTime;
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _selectHairstyle() async {
    final result = await Navigator.of(context).push<HairstyleModel>(
      MaterialPageRoute(
        builder: (_) => HairstyleGallery(selectedId: _selectedHairstyle?.id),
      ),
    );
    if (result != null) {
      setState(() {
        if (result.id == 'none') {
          _selectedHairstyle = null;
        } else {
          _selectedHairstyle = result;
        }
      });
    }
  }

  Future<void> _saveAppointment() async {
    if (_isSaving || _saveCompleted) return;
    setState(() => _isSaving = true);
    try {
      // Validate
      if (_customerName.trim().isEmpty && _selectedCustomer == null) {
        _showSnackBar('Lütfen müşteri adı girin');
        return;
      }
      if (_selectedTime == null) {
        _showSnackBar('Lütfen saat seçin');
        return;
      }
      if (_selectedService == null) {
        _showSnackBar('Lütfen hizmet seçin');
        return;
      }

      final name = _selectedCustomer?.name ?? _customerName;
      final timeStr =
          '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';

      final validationAppointment = Appointment(
        customerName: _selectedCustomer?.name ?? _customerName,
        appointmentDate: _selectedDate,
        appointmentTime: timeStr,
        durationMinutes: _selectedService?.durationMinutes ?? 30,
      );
      if (validationAppointment.fullDateTime.isAfter(DateTime.now())) {
        final workingIntervals = await _dbService.getWorkingIntervals();
        if (workingIntervals.isNotEmpty &&
            !isInsideWorkingHours(validationAppointment, workingIntervals)) {
          _showSnackBar('Randevu çalışma saatleri dışında kalıyor.');
          return;
        }
        final closedBlocks = await _dbService.getClosedTimeBlocks();
        final blocked = closedBlocks
            .where((block) => overlapsClosedTime(validationAppointment, block))
            .firstOrNull;
        if (blocked != null) {
          _showSnackBar(
            blocked.reason == null
                ? 'Seçilen zaman kapalı olarak işaretlenmiş.'
                : 'Kapalı zaman: ${blocked.reason}',
          );
          return;
        }
      }

      // No restrictions for past appointments so barbers can log recent walk-ins

      // Check if time slot is taken
      final isTaken = await _dbService.isTimeSlotTaken(
        _selectedDate,
        timeStr,
        durationMinutes: _selectedService?.durationMinutes ?? 30,
        excludeId: widget.appointmentToEdit?.id,
      );
      if (isTaken) {
        _showSnackBar('Bu saatte zaten bir randevu var!');
        return;
      }

      final customer = await AppointmentCustomerService.resolve(
        selectedCustomerId: _selectedCustomer?.id,
        name: name,
        phone: _phoneController.text,
      );

      var status =
          widget.appointmentToEdit?.status ?? AppointmentStatus.planned;

      // Automatically revert completion if they reschedule it to a future time
      final targetDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      if (status == AppointmentStatus.completed &&
          targetDateTime.isAfter(DateTime.now())) {
        status = AppointmentStatus.planned;
      }

      // Create appointment
      final appointment = Appointment(
        id: widget.appointmentToEdit?.id,
        customerId: customer.id,
        customerName: customer.name,
        appointmentDate: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        ),
        appointmentTime: timeStr,
        hairstyleId: _selectedHairstyle?.id,
        hairstyleName: _selectedHairstyle?.name,
        serviceId: _selectedService?.id,
        serviceName: _selectedService?.name,
        durationMinutes: _selectedService?.durationMinutes ?? 30,
        priceCents: _selectedService?.priceCents,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        status: status,
        createdAt: widget.appointmentToEdit?.createdAt,
      );

      if (widget.appointmentToEdit != null) {
        await _dbService.updateAppointment(appointment);
        await NotificationService.instance.cancelAlarm(appointment.id!);
        if (appointment.shouldHaveAlarm) {
          await NotificationService.instance.scheduleAlarm(appointment);
        }
        if (mounted) {
          _saveCompleted = true;
          _showSnackBar('Randevu güncellendi!');
          Navigator.of(context).pop(true);
        }
        return;
      }

      final id = await _dbService.insertAppointment(appointment);

      // Schedule alarm
      final savedAppointment = appointment.copyWith(id: id);
      await NotificationService.instance.scheduleAlarm(savedAppointment);

      if (mounted) {
        _saveCompleted = true;
        _showSnackBar(AppStrings.appointmentCreated);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Kayıt Hatası: $e');
      }
    } finally {
      if (mounted && !_saveCompleted) setState(() => _isSaving = false);
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

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('d MMMM yyyy, EEEE', 'tr_TR');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          widget.appointmentToEdit != null
              ? 'Randevuyu Düzenle'
              : 'Yeni Randevu',
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer field
            _buildLabel('Müşteri'),
            const SizedBox(height: 8),
            if (widget.appointmentToEdit != null || _isRepeating)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    if (_selectedCustomer?.photoPath != null &&
                        _selectedCustomer!.photoPath!.isNotEmpty)
                      ClipOval(
                        child: Image.file(
                          File(_selectedCustomer!.photoPath!),
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.person,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    const SizedBox(width: 12),
                    Text(
                      _customerName,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomerSearchWidget(
                    initialValue: null,
                    onCustomerSelected: (customer) {
                      setState(() {
                        _selectedCustomer = customer;
                        _phoneController.text = customer.phone ?? '';
                      });
                    },
                    onNewCustomerName: (name) {
                      setState(() {
                        _customerName = name;
                        if (_selectedCustomer != null) _phoneController.clear();
                        _selectedCustomer = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Mevcut müşteri için listeden seçin. Yalnızca ad yazarsanız yeni müşteri kaydedilir.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        counterText: "",
                        hintText: 'Telefon (Opsiyonel)',
                        hintStyle: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.phone,
                          color: AppColors.textSecondary,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            if (_isRepeating)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Tekrar şablonu: müşteri, kayıtlı fotoğraf, hizmet ve model korundu. Yalnız tarih ve saat seçin.',
                  style: TextStyle(color: AppColors.gold),
                ),
              ),
            if (_isRepeating) const SizedBox(height: 24),

            // Date field
            _buildLabel('Tarih'),
            const SizedBox(height: 8),
            _buildSelectorButton(
              icon: Icons.calendar_today,
              text: dateFormat.format(_selectedDate),
              onTap: _pickDate,
            ),

            const SizedBox(height: 24),

            // Time field
            _buildLabel('Saat'),
            const SizedBox(height: 8),
            _buildSelectorButton(
              icon: Icons.access_time,
              text: _selectedTime != null
                  ? '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                  : 'Lütfen saat belirleyin...',
              onTap: _pickTime,
              isEmpty: _selectedTime == null,
            ),

            const SizedBox(height: 24),

            _buildLabel('Hizmet'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<BarberService>(
                  value: _selectedService,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  hint: const Text(
                    'Hizmet seçin',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  items: _services
                      .map(
                        (service) => DropdownMenuItem(
                          value: service,
                          child: Text(
                            '${service.name} • ${service.durationMinutes} dk',
                            style: const TextStyle(color: AppColors.white),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isRepeating
                      ? null
                      : (service) => setState(() => _selectedService = service),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Hairstyle field
            _buildLabel('Saç Modeli (Opsiyonel)'),
            const SizedBox(height: 8),
            _buildSelectorButton(
              icon: Icons.content_cut,
              text: _selectedHairstyle?.name ?? 'Model seçin...',
              onTap: _isRepeating ? () {} : _selectHairstyle,
              isEmpty: _selectedHairstyle == null,
            ),

            const SizedBox(height: 24),

            // Notes field
            _buildLabel('Not (opsiyonel)'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _notesController,
                readOnly: _isRepeating,
                style: const TextStyle(color: AppColors.white, fontSize: 16),
                maxLines: 2,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Ek bilgi...',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveAppointment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  widget.appointmentToEdit != null
                      ? 'GÜNCELLE'
                      : 'RANDEVU OLUŞTUR',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.gold,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSelectorButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    bool isEmpty = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isEmpty ? AppColors.textSecondary : AppColors.gold,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                color: isEmpty ? AppColors.textSecondary : AppColors.white,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

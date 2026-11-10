import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/appointment.dart';
import '../models/customer.dart';
import '../models/barber_service.dart';
import '../models/working_schedule.dart';
import '../services/appointment_form_gateway.dart';
import '../services/alarm_scheduling.dart';
import '../widgets/alarm_feedback.dart';
import '../utils/constants.dart';
import '../utils/route_result.dart';
import '../utils/hairstyle_data.dart';
import '../widgets/customer_search.dart';
import 'hairstyle_gallery.dart';

class AddAppointmentScreen extends StatefulWidget {
  final AppointmentFormGateway gateway;
  final DateTime? initialDate;
  final Appointment? appointmentToEdit;
  final Appointment? appointmentToRepeat;

  const AddAppointmentScreen({
    super.key,
    this.gateway = const AppointmentFormGateway(),
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

  bool _loading = true;
  bool _loadingRequest = false;
  String? _loadError;
  String? _saveError;
  Object? _initialForm;
  bool _allowExit = false;
  bool _askingExit = false;

  Object get _formValue => (
    _selectedDate,
    _selectedTime,
    _selectedCustomer?.id,
    _customerName,
    _selectedService?.id,
    _selectedHairstyle?.id,
    _notesController.text,
    _phoneController.text,
  );
  bool get _dirty => _initialForm != null && _initialForm != _formValue;
  void _textChanged() {
    if (mounted && !_loading) setState(() {});
  }

  Future<void> _confirmExit() async {
    if (_isSaving || _askingExit || !_dirty) return;
    final route = ModalRoute.of(context);
    _askingExit = true;
    try {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Değişiklikler kaydedilmedi'),
          content: const Text(
            'Girdiğiniz bilgileri bırakıp çıkmak istiyor musunuz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Düzenlemeye devam et'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydetmeden çık'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        setState(() => _allowExit = true);
        finishRoute(route);
      }
    } finally {
      _askingExit = false;
    }
  }

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
    } else {
      _selectedDate = widget.initialDate ?? DateTime.now();
    }
    _notesController.addListener(_textChanged);
    _phoneController.addListener(_textChanged);
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    if (!mounted || _loadingRequest) return;
    _loadingRequest = true;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final allServices = await widget.gateway.services();
      final source = widget.appointmentToEdit ?? widget.appointmentToRepeat;
      final customer = source?.customerId == null
          ? null
          : await widget.gateway.customer(source!.customerId!);
      if (source?.customerId != null && customer == null) {
        throw StateError('Randevunun müşteri kaydı bulunamadı.');
      }
      if (!mounted) return;
      final editing = widget.appointmentToEdit != null;
      final available = allServices
          .where(
            (service) =>
                service.isActive ||
                (editing && service.id == source?.serviceId),
          )
          .toList();
      final previousServiceId = source?.serviceId;
      final needsNewService =
          _isRepeating &&
          previousServiceId != null &&
          !available.any((service) => service.id == previousServiceId);
      final selected = needsNewService
          ? null
          : selectServiceForAppointment(available, previousServiceId);
      setState(() {
        _services = available;
        _selectedService = selected;
        _selectedCustomer = customer;
        if (customer != null) _phoneController.text = customer.phone ?? '';
        _initialForm = _formValue;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error is StateError
            ? error.message
            : 'Randevu bilgileri yüklenemedi. Yeniden deneyin.';
      });
    } finally {
      _loadingRequest = false;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
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
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();
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
    if (result != null && mounted) {
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
    if (_isSaving || _saveCompleted || _loading || _loadError != null) return;
    final route = ModalRoute.of(context);
    FocusScope.of(context).unfocus();
    final selectedPhone = _phoneController.text;
    final selectedNotes = _notesController.text;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });
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
        final workingIntervals = await widget.gateway.workingIntervals();
        if (workingIntervals.isNotEmpty &&
            !isInsideWorkingHours(validationAppointment, workingIntervals)) {
          _showSnackBar('Randevu çalışma saatleri dışında kalıyor.');
          return;
        }
        final closedBlocks = await widget.gateway.closedBlocks();
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
      final isTaken = await widget.gateway.isTaken(
        validationAppointment,
        excludeId: widget.appointmentToEdit?.id,
      );
      if (isTaken) {
        _showSnackBar('Bu saatte zaten bir randevu var!');
        return;
      }

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
        customerId: _selectedCustomer?.id,
        customerName: name,
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
        notes: selectedNotes.isNotEmpty ? selectedNotes : null,
        status: status,
        createdAt: widget.appointmentToEdit?.createdAt,
      );

      final savedAppointment = await widget.gateway.save(
        appointment: appointment,
        selectedCustomerId:
            _selectedCustomer?.id ??
            (widget.appointmentToEdit ?? widget.appointmentToRepeat)
                ?.customerId,
        phone: selectedPhone,
        expectedStatus: widget.appointmentToEdit?.status,
      );
      // Once committed, alarm failure must never offer a second DB insert.
      _saveCompleted = true;
      AlarmScheduleResult alarmResult;
      try {
        alarmResult = await widget.gateway.syncAlarm(
          savedAppointment,
          editing: widget.appointmentToEdit != null,
        );
      } catch (_) {
        alarmResult = AlarmScheduleResult.failed;
      }
      if (mounted) {
        setState(() => _isSaving = false);
        if (alarmResult == AlarmScheduleResult.failed) {
          showAppointmentAlarmWarning(
            ScaffoldMessenger.of(context),
            savedAppointment,
          );
        } else {
          _showSnackBar(
            widget.appointmentToEdit != null
                ? 'Randevu güncellendi!'
                : AppStrings.appointmentCreated,
          );
        }
        finishRoute(route, true);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _saveError = e is StateError
              ? e.message
              : 'Randevu kaydedilemedi. Bilgileriniz korunuyor; yeniden deneyin.',
        );
      }
    } finally {
      if (mounted && !_saveCompleted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
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

    return PopScope(
      canPop: !_isSaving && (_saveCompleted || !_dirty || _allowExit),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
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
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadInitial,
                          child: const Text('Yeniden dene'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : AbsorbPointer(
                absorbing: _isSaving,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSaving) ...[
                        const LinearProgressIndicator(),
                        const Text('Randevu kaydediliyor…'),
                        const SizedBox(height: 12),
                      ],
                      if (_services.isEmpty) ...[
                        const Text(
                          'Randevu oluşturmak için Yönetim → Hizmetler bölümünden aktif bir hizmet ekleyin.',
                        ),
                        const SizedBox(height: 12),
                      ],
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
                              Expanded(
                                child: Text(
                                  _customerName,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                  ),
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
                                  if (_selectedCustomer != null) {
                                    _phoneController.clear();
                                  }
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
                                    color: AppColors.textSecondary.withValues(
                                      alpha: 0.6,
                                    ),
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
                                      style: const TextStyle(
                                        color: AppColors.white,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (service) =>
                                setState(() => _selectedService = service),
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
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Ek bilgi...',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      if (_saveError != null) ...[
                        Text(
                          _saveError!,
                          style: const TextStyle(color: AppColors.red),
                        ),
                        const SizedBox(height: 12),
                      ],
                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveAppointment,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.background,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 4,
                          ),
                          child: Text(
                            _isSaving
                                ? 'KAYDEDİLİYOR…'
                                : widget.appointmentToEdit != null
                                ? 'GÜNCELLE'
                                : 'RANDEVU OLUŞTUR',
                            textAlign: TextAlign.center,
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
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: isEmpty ? AppColors.textSecondary : AppColors.white,
                  fontSize: 16,
                ),
              ),
            ),
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

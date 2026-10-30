import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/working_schedule.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class WorkingHoursScreen extends StatefulWidget {
  const WorkingHoursScreen({super.key});

  @override
  State<WorkingHoursScreen> createState() => _WorkingHoursScreenState();
}

class _WorkingHoursScreenState extends State<WorkingHoursScreen> {
  static const _dayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  final _db = DatabaseService.instance;
  final Map<int, WorkingInterval?> _days = {};
  List<ClosedTimeBlock> _blocks = [];
  int _appointmentCapacity = 1;
  bool _paymentEnabled = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final intervals = await _db.getWorkingIntervals();
      final blocks = await _db.getClosedTimeBlocks();
      final capacity = await _db.getAppointmentCapacity();
      final paymentEnabled = await _db.isPaymentEnabled();
      if (!mounted) return;
      setState(() {
        for (var day = 1; day <= 7; day++) {
          _days[day] = intervals
              .where((item) => item.weekday == day)
              .firstOrNull;
        }
        _blocks = blocks;
        _appointmentCapacity = capacity;
        _paymentEnabled = paymentEnabled;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Working hours could not load: $error');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Future<int?> _pickMinute(int initial) async {
    var selected = initial;
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: 300,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('İptal'),
                  ),
                  const Text('Saat seç'),
                  TextButton(
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text('Bitti'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(brightness: Brightness.dark),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: true,
                  initialDateTime: DateTime(
                    2026,
                    1,
                    1,
                    initial ~/ 60,
                    initial % 60,
                  ),
                  onDateTimeChanged: (value) {
                    selected = value.hour * 60 + value.minute;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  Future<void> _setCapacity() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: AppointmentCapacityPicker(
          currentCapacity: _appointmentCapacity,
          onSelected: (value) => Navigator.pop(context, value),
        ),
      ),
    );
    if (selected == null || selected == _appointmentCapacity) return;
    if (mounted) setState(() => _appointmentCapacity = selected);
    await _db.setAppointmentCapacity(selected);
  }

  Future<void> _setPaymentEnabled(bool enabled) async {
    await _db.setPaymentEnabled(enabled);
    if (mounted) setState(() => _paymentEnabled = enabled);
  }

  Future<void> _editDay(int day) async {
    final current = _days[day];
    var start = current?.startMinute ?? 540;
    var end = current?.endMinute ?? 1080;
    final result = await showDialog<WorkingInterval>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(_dayNames[day - 1]),
          content: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final value = await _pickMinute(start);
                    if (value != null) setDialogState(() => start = value);
                  },
                  child: Text(_time(start)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('–'),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final value = await _pickMinute(end == 1440 ? 1439 : end);
                    if (value != null) setDialogState(() => end = value);
                  },
                  child: Text(_time(end)),
                ),
              ),
            ],
          ),
          actions: [
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  WorkingInterval(weekday: day, startMinute: 0, endMinute: 1),
                ),
                child: const Text('Günü kapat'),
              ),
            FilledButton(
              onPressed: start < end
                  ? () => Navigator.pop(
                      context,
                      WorkingInterval(
                        weekday: day,
                        startMinute: start,
                        endMinute: end,
                      ),
                    )
                  : null,
              child: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _days[day] = result.startMinute == 0 && result.endMinute == 1
          ? null
          : result;
    });
  }

  Future<void> _save() async {
    await _db.replaceWorkingIntervals(
      _days.values.whereType<WorkingInterval>().toList(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Çalışma saatleri kaydedildi.')),
    );
  }

  Future<void> _addBlock() async {
    var start = DateTime.now().add(const Duration(hours: 1));
    var end = start.add(const Duration(hours: 1));
    final reason = TextEditingController();
    final result = await showDialog<ClosedTimeBlock>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Kapalı zaman ekle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Başlangıç'),
                subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(start)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: start,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(start),
                  );
                  if (time != null) {
                    setDialogState(
                      () => start = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                title: const Text('Bitiş'),
                subtitle: Text(DateFormat('dd.MM.yyyy HH:mm').format(end)),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: end,
                    firstDate: start,
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(end),
                  );
                  if (time != null) {
                    setDialogState(
                      () => end = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ),
                    );
                  }
                },
              ),
              TextField(
                controller: reason,
                maxLength: 140,
                decoration: const InputDecoration(
                  labelText: 'Neden (opsiyonel)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: start.isBefore(end)
                  ? () => Navigator.pop(
                      context,
                      ClosedTimeBlock(
                        startAt: start,
                        endAt: end,
                        reason: reason.text.trim().isEmpty
                            ? null
                            : reason.text.trim(),
                      ),
                    )
                  : null,
              child: const Text('Ekle'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (result == null) return;
    await _db.insertClosedTimeBlock(result);
    await _load();
  }

  Future<void> _deleteBlock(ClosedTimeBlock block) async {
    if (block.id == null) return;
    await _db.deleteClosedTimeBlock(block.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çalışma saatleri'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.save))],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: AppColors.surface,
                  child: ListTile(
                    onTap: _setCapacity,
                    leading: const Icon(Icons.people_outline),
                    title: const Text('Aynı anda müşteri sayısı'),
                    subtitle: Text('$_appointmentCapacity müşteri'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                Card(
                  color: AppColors.surface,
                  child: SwitchListTile(
                    secondary: const Icon(Icons.payments_outlined),
                    title: const Text('Ödeme kayıtları'),
                    subtitle: Text(
                      _paymentEnabled
                          ? 'Tamamlanan randevularda ödeme almayı gösterir.'
                          : 'Ödeme istemleri ve günlük tahsilat gizlenir.',
                    ),
                    value: _paymentEnabled,
                    onChanged: _setPaymentEnabled,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Haftalık program',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                for (var day = 1; day <= 7; day++)
                  Card(
                    color: AppColors.surface,
                    child: ListTile(
                      onTap: () => _editDay(day),
                      title: Text(_dayNames[day - 1]),
                      subtitle: Text(
                        _days[day] == null
                            ? 'Kapalı'
                            : '${_time(_days[day]!.startMinute)}–${_time(_days[day]!.endMinute)}',
                      ),
                      trailing: const Icon(Icons.edit),
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Özel kapalı zamanlar',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _addBlock,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                if (_blocks.isEmpty)
                  const Text(
                    'Tanımlı kapalı zaman yok.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                for (final block in _blocks)
                  Card(
                    color: AppColors.surface,
                    child: ListTile(
                      title: Text(block.reason ?? 'Kapalı'),
                      subtitle: Text(
                        '${DateFormat('dd.MM.yyyy HH:mm').format(block.startAt)} – ${DateFormat('dd.MM.yyyy HH:mm').format(block.endAt)}',
                      ),
                      trailing: IconButton(
                        onPressed: () => _deleteBlock(block),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class AppointmentCapacityPicker extends StatelessWidget {
  const AppointmentCapacityPicker({
    super.key,
    required this.currentCapacity,
    required this.onSelected,
  });

  final int currentCapacity;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text('Aynı anda müşteri sayısı')),
        for (var value = 1; value <= 4; value++)
          ListTile(
            title: Text('$value müşteri'),
            trailing: value == currentCapacity
                ? const Icon(Icons.check, color: AppColors.gold)
                : null,
            onTap: () => onSelected(value),
          ),
      ],
    );
  }
}

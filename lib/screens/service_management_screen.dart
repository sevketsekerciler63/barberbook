import 'package:flutter/material.dart';
import '../models/barber_service.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';
import '../utils/money.dart';
import '../utils/route_result.dart';

class ServiceManagementGateway {
  const ServiceManagementGateway();
  Future<List<BarberService>> load() =>
      DatabaseService.instance.getServices(activeOnly: false);
  Future<void> save(BarberService service) async {
    if (service.id == null) {
      await DatabaseService.instance.insertService(service);
    } else {
      await DatabaseService.instance.updateService(service);
    }
  }
}

class ServiceManagementScreen extends StatefulWidget {
  final ServiceManagementGateway gateway;
  const ServiceManagementScreen({
    super.key,
    this.gateway = const ServiceManagementGateway(),
  });

  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<BarberService> _services = [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final services = List<BarberService>.of(await widget.gateway.load());
      services.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _services = services;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _edit([BarberService? existing]) async {
    if (_editing || _loading || _loadFailed) return;
    setState(() => _editing = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ServiceEditor(existing: existing, gateway: widget.gateway),
      );
      if (saved == true && mounted) await _load();
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  String _price(BarberService service) {
    if (service.priceCents == null) return 'Fiyat belirtilmedi';
    return '${(service.priceCents! / 100).toStringAsFixed(2)} ₺';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hizmetler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _loadFailed || _editing ? null : () => _edit(),
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.add),
        label: const Text('Hizmet ekle'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
            )
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Hizmetler yüklenemedi.'),
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            )
          : _services.isEmpty
          ? const Center(child: Text('Henüz hizmet eklenmedi.'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: _services.length,
              itemBuilder: (context, index) {
                final service = _services[index];
                return Card(
                  color: AppColors.surface,
                  child: ListTile(
                    onTap: _editing ? null : () => _edit(service),
                    leading: Icon(
                      service.isActive
                          ? Icons.content_cut
                          : Icons.archive_outlined,
                      color: service.isActive
                          ? AppColors.gold
                          : AppColors.textSecondary,
                    ),
                    title: Text(service.name),
                    subtitle: Text(
                      '${service.durationMinutes} dk • ${_price(service)}${service.isActive ? '' : ' • Arşivlenmiş'}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              },
            ),
    );
  }
}

class _ServiceEditor extends StatefulWidget {
  final BarberService? existing;
  final ServiceManagementGateway gateway;
  const _ServiceEditor({required this.existing, required this.gateway});

  @override
  State<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends State<_ServiceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _duration;
  late final TextEditingController _price;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _duration = TextEditingController(
      text: (existing?.durationMinutes ?? 30).toString(),
    );
    _price = TextEditingController(
      text: existing?.priceCents == null
          ? ''
          : (existing!.priceCents! / 100).toStringAsFixed(2),
    );
    _active = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    final minutes = int.tryParse(_duration.text.trim());
    final priceText = _price.text.trim();
    final cents = parseMoneyCents(priceText, emptyAsZero: false);
    if (name.isEmpty ||
        name.length > 60 ||
        minutes == null ||
        minutes < 1 ||
        minutes > 480) {
      setState(
        () => _error = 'Hizmet adı 1–60 karakter, süre 1–480 dakika olmalıdır.',
      );
      return;
    }
    if (priceText.isNotEmpty && cents == null) {
      setState(() => _error = 'Fiyatı en fazla iki ondalık basamakla girin.');
      return;
    }
    final service = BarberService(
      id: widget.existing?.id,
      name: name,
      durationMinutes: minutes,
      priceCents: cents,
      isActive: _active,
    );
    final route = ModalRoute.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.gateway.save(service);
      if (!mounted) return;
      setState(() => _saving = false);
      finishRoute(route, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is StateError
            ? error.message.toString()
            : 'Hizmet kaydedilemedi. Bilgileriniz korundu; yeniden deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.existing == null ? 'Hizmet ekle' : 'Hizmeti düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_saving) const LinearProgressIndicator(),
            TextField(
              controller: _name,
              enabled: !_saving,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Hizmet adı'),
            ),
            TextField(
              controller: _duration,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Süre (dakika)'),
            ),
            TextField(
              controller: _price,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Fiyat (₺, opsiyonel)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yeni randevulara açık'),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
        ),
      ],
    ),
  );
}

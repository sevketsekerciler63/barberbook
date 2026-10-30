import 'package:flutter/material.dart';
import '../models/barber_service.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});

  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  final _db = DatabaseService.instance;
  List<BarberService> _services = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = await _db.getServices(activeOnly: false);
    services.sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (!mounted) return;
    setState(() {
      _services = services;
      _loading = false;
    });
  }

  Future<void> _edit([BarberService? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final duration = TextEditingController(
      text: (existing?.durationMinutes ?? 30).toString(),
    );
    final price = TextEditingController(
      text: existing?.priceCents == null
          ? ''
          : (existing!.priceCents! / 100).toStringAsFixed(2),
    );
    var active = existing?.isActive ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(existing == null ? 'Hizmet ekle' : 'Hizmeti düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(labelText: 'Hizmet adı'),
                ),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Süre (dakika)'),
                ),
                TextField(
                  controller: price,
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
                  value: active,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                final cleanName = name.text.trim();
                final minutes = int.tryParse(duration.text.trim());
                final normalizedPrice = price.text.trim().replaceAll(',', '.');
                final priceValue = normalizedPrice.isEmpty
                    ? null
                    : double.tryParse(normalizedPrice);
                if (cleanName.isEmpty ||
                    minutes == null ||
                    minutes < 1 ||
                    minutes > 480 ||
                    (normalizedPrice.isNotEmpty &&
                        (priceValue == null || priceValue < 0))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ad, süre veya fiyat geçersiz.'),
                    ),
                  );
                  return;
                }
                final duplicate = _services.any(
                  (service) =>
                      service.id != existing?.id &&
                      service.isActive &&
                      active &&
                      service.name.trim().toLowerCase() ==
                          cleanName.toLowerCase(),
                );
                if (duplicate) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Aynı adlı aktif hizmet zaten var.'),
                    ),
                  );
                  return;
                }

                final service = BarberService(
                  id: existing?.id,
                  name: cleanName,
                  durationMinutes: minutes,
                  priceCents: priceValue == null
                      ? null
                      : (priceValue * 100).round(),
                  isActive: active,
                );
                if (existing == null) {
                  await _db.insertService(service);
                } else {
                  await _db.updateService(service);
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    name.dispose();
    duration.dispose();
    price.dispose();
    if (saved == true) await _load();
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
        onPressed: () => _edit(),
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.add),
        label: const Text('Hizmet ekle'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold),
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
                    onTap: () => _edit(service),
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

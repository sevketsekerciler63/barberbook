import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/backup_preview.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<File> _backups = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final backups = await BackupService.instance.listBackups();
      if (mounted) {
        setState(() {
          _backups = backups;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yedekler yüklenemedi. Yeniden deneyin.'),
          ),
        );
      }
    }
  }

  Future<void> _create({bool omitMissingPhotos = false}) async {
    setState(() => _busy = true);
    try {
      final file = await BackupService.instance.createBackup(
        omitMissingPhotos: omitMissingPhotos,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yedek oluşturuldu: ${file.path}')),
        );
      }
      await _load();
    } on MissingBackupPhotosException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final omit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Bazı fotoğraflar bulunamadı'),
          content: Text(
            '${error.count} fotoğraf dosyası eksik. Müşteri, randevu ve ödeme verilerini koruyan bir yedek oluşturulsun mu? Yalnız yedek kopyasındaki eksik fotoğraf bağlantıları çıkarılır; bu cihazın verisi değişmez.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eksik fotoğraflar olmadan yedekle'),
            ),
          ],
        ),
      );
      if (omit == true && mounted) await _create(omitMissingPhotos: true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yedekleme başarısız: $error')));
      }
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'db'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _restore(File(path));
  }

  Future<void> _shareBackup(File file) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType: file.path.endsWith('.zip')
                ? 'application/zip'
                : 'application/x-sqlite3',
          ),
        ],
        subject: 'BarberBook yedeği',
        text: 'BarberBook veri ve müşteri fotoğrafları yedeği',
      ),
    );
  }

  String _previewText(BackupPreview preview) =>
      'Şema: v${preview.schemaVersion}\n'
      'Müşteriler: ${preview.customerCount}\n'
      'Randevular: ${preview.appointmentCount}\n'
      'Hizmetler: ${preview.serviceCount}\n'
      'Ödemeler: ${preview.paymentCount}\n'
      'Kasa hareketleri: ${preview.transactionCount}';

  Future<void> _restore(File file) async {
    setState(() => _busy = true);
    BackupPreview preview;
    try {
      preview = await BackupService.instance.previewBackup(file);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yedek doğrulanamadı: $error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yedeği geri yükle'),
        content: Text(
          '${_previewText(preview)}\n\nMevcut verinin ayrıca güvenlik yedeği alınacak. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geri yükle'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _performRestore(file);
  }

  Future<void> _performRestore(
    File file, {
    bool omitMissingSafetyPhotos = false,
  }) async {
    setState(() => _busy = true);
    try {
      final result = await BackupService.instance.restoreBackup(
        file,
        omitMissingSafetyPhotos: omitMissingSafetyPhotos,
        synchronizeAlarms:
            NotificationService.instance.synchronizeWithAppointments,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        if (result.alarmsSynchronized == true) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Yedek geri yüklendi.')),
          );
        } else {
          _showAlarmWarning(messenger);
        }
        setState(() => _busy = false);
        Navigator.of(context).pop(true);
      }
    } on MissingBackupPhotosException catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Güvenlik yedeğinde eksik fotoğraflar'),
          content: Text(
            'Bu cihazda ${error.count} fotoğraf bulunamadı. Önce eksik fotoğraflar hariç bir güvenlik yedeği alınacak, ardından seçtiğiniz yedek geri yüklenecek. Devam edilsin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Devam et'),
            ),
          ],
        ),
      );
      if (approved == true && mounted) {
        await _performRestore(file, omitMissingSafetyPhotos: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geri yükleme başarısız: $error')),
        );
      }
    }
  }

  void _showAlarmWarning(ScaffoldMessengerState messenger) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Veriler geri yüklendi; randevu alarmları yeniden kurulamadı.',
        ),
        duration: const Duration(seconds: 15),
        action: SnackBarAction(
          label: 'Alarmları yeniden dene',
          onPressed: () async {
            try {
              await NotificationService.instance.synchronizeWithAppointments();
              if (messenger.mounted) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Randevu alarmları güncellendi.'),
                  ),
                );
              }
            } catch (_) {
              if (messenger.mounted) _showAlarmWarning(messenger);
            }
          },
        ),
      ),
    );
  }

  String _label(File file) {
    final modified = file.lastModifiedSync();
    final sizeKb = file.lengthSync() / 1024;
    return '${DateFormat('dd.MM.yyyy HH:mm').format(modified)} • ${sizeKb.toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Yedekleme'),
          actions: [
            IconButton(
              tooltip: 'ZIP veya eski DB yedeğini içe aktar',
              onPressed: _busy ? null : _importBackup,
              icon: const Icon(Icons.file_open_outlined),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _busy ? null : () => _create(),
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.background,
          icon: const Icon(Icons.backup),
          label: const Text('Yeni yedek'),
        ),
        body: _busy
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              )
            : _backups.isEmpty
            ? const Center(child: Text('Henüz yedek oluşturulmadı.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: _backups.length,
                itemBuilder: (context, index) {
                  final file = _backups[index];
                  return Card(
                    color: AppColors.surface,
                    child: ListTile(
                      leading: const Icon(Icons.storage, color: AppColors.gold),
                      title: Text('Yedek ${_backups.length - index}'),
                      subtitle: Text(_label(file)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Paylaş',
                            onPressed: () => _shareBackup(file),
                            icon: const Icon(Icons.share_outlined),
                          ),
                          TextButton(
                            onPressed: () => _restore(file),
                            child: const Text('Geri yükle'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

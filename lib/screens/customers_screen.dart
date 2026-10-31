import '../services/latest_request.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../models/appointment.dart';
import '../models/customer_photo.dart';
import '../services/database_service.dart';
import '../services/customer_photo_storage.dart';
import '../services/whatsapp_service.dart';
import '../utils/constants.dart';
import '../utils/hairstyle_data.dart';
import '../screens/hairstyle_gallery.dart';
import '../screens/add_appointment_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class CustomerNotesField extends StatelessWidget {
  const CustomerNotesField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLength: Customer.maxNotesLength,
      maxLines: 3,
      minLines: 2,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(color: AppColors.white),
      decoration: const InputDecoration(
        labelText: 'Müşteri Notu (Opsiyonel)',
        alignLabelWithHint: true,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _dbService = DatabaseService.instance;
  final _searchController = TextEditingController();
  List<Customer> _customers = [];
  Map<int, Appointment> _pendingAppointments = {};
  bool _isLoading = true;
  String? _loadError;
  final _customerRequest = LatestRequest();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerRequest.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() => _queryCustomers(_searchController.text);
  Future<void> _searchCustomers(String query) => _queryCustomers(query);

  Future<void> _queryCustomers(String query) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    await _customerRequest.run(
      load: () async {
        final customers = query.trim().isEmpty
            ? await _dbService.getAllCustomers()
            : await _dbService.searchCustomers(query);
        final upcoming = await _dbService.getUpcomingAppointments();
        final pending = <int, Appointment>{};
        for (final appointment in upcoming) {
          final id = appointment.customerId;
          if (id != null) pending.putIfAbsent(id, () => appointment);
        }
        return (customers: customers, pending: pending);
      },
      apply: (data) {
        if (mounted) {
          setState(() {
            _customers = data.customers;
            _pendingAppointments = data.pending;
            _isLoading = false;
          });
        }
      },
      onError: (_, _) {
        if (mounted) {
          setState(() {
            _customers = [];
            _isLoading = false;
            _loadError = 'Müşteriler yüklenemedi. Aramayı yeniden deneyin.';
          });
        }
      },
    );
  }

  Future<void> _deleteCustomer(Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Müşteriyi Sil',
          style: TextStyle(color: AppColors.white),
        ),
        content: Text(
          '${customer.name} silinecek. Emin misiniz?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'İptal',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && customer.id != null) {
      // Customer deletion detaches the card; retained appointments and alarms stay.
      await _dbService.deleteCustomer(customer.id!);
      await _loadCustomers();
      if (_searchController.text.isNotEmpty) {
        await _searchCustomers(_searchController.text);
      }
    }
  }

  void _showAddOrEditCustomerDialog([Customer? customer]) {
    final nameController = TextEditingController(text: customer?.name);
    final phoneController = TextEditingController(text: customer?.phone);
    final notesController = TextEditingController(text: customer?.notes);
    String? selectedHairstyleName = customer?.favoriteHairstyle;
    String? selectedPhotoPath = customer?.photoPath;
    var selectedPhotoSource = CustomerPhotoSource.gallery;
    var selectedPhotoType = CustomerPhotoType.reference;
    var photoChanged = false;
    final isEditing = customer != null;
    var saving = false;
    String? uncommittedPhotoPath;
    Future<bool> confirmManagedPhotoChange(String action) async {
      if (selectedPhotoPath == null) return true;
      return await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: AppColors.surface,
              title: Text(action),
              content: const Text(
                'Mevcut fotoğraf geçmişte kalır; müşteri kartındaki aktif fotoğraf değişir. Devam etmek istiyor musunuz?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Devam et'),
                ),
              ],
            ),
          ) ??
          false;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing ? 'Müşteriyi Düzenle' : 'Yeni Müşteri Ekle',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: AppColors.white),
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    style: const TextStyle(color: AppColors.white),
                    decoration: const InputDecoration(
                      counterText: "",
                      labelText: 'Telefon Numarası (Opsiyonel)',
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomerNotesField(controller: notesController),
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        _customerAvatar(
                          Customer(
                            name: nameController.text.isEmpty
                                ? 'M'
                                : nameController.text,
                            photoPath: selectedPhotoPath,
                          ),
                          radius: 44,
                          fontSize: 32,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!await confirmManagedPhotoChange(
                                  'Aktif fotoğraf değiştirilsin mi?',
                                )) {
                                  return;
                                }
                                final result = await FilePicker.pickFiles(
                                  type: FileType.image,
                                );
                                final photoPath = result?.files.single.path;
                                if (photoPath == null) return;
                                setModalState(() {
                                  selectedPhotoPath = photoPath;
                                  selectedPhotoSource =
                                      CustomerPhotoSource.gallery;
                                  photoChanged = true;
                                });
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: Text(
                                selectedPhotoPath == null
                                    ? 'Fotoğraf Seç'
                                    : 'Fotoğrafı Değiştir',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                if (!await confirmManagedPhotoChange(
                                  'Aktif fotoğraf değiştirilsin mi?',
                                )) {
                                  return;
                                }
                                final photo = await ImagePicker().pickImage(
                                  source: ImageSource.camera,
                                  imageQuality: 90,
                                );
                                if (photo == null) return;
                                setModalState(() {
                                  selectedPhotoPath = photo.path;
                                  selectedPhotoSource =
                                      CustomerPhotoSource.camera;
                                  photoChanged = true;
                                });
                              },
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Kamera'),
                            ),
                            if (selectedPhotoPath != null)
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (!await confirmManagedPhotoChange(
                                    'Aktif fotoğraf kaldırılsın mı?',
                                  )) {
                                    return;
                                  }
                                  setModalState(() {
                                    selectedPhotoPath = null;
                                    photoChanged = true;
                                  });
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Kaldır'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.red,
                                ),
                              ),
                          ],
                        ),
                        if (selectedPhotoPath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: SegmentedButton<CustomerPhotoType>(
                              segments: const [
                                ButtonSegment(
                                  value: CustomerPhotoType.reference,
                                  label: Text('Referans'),
                                ),
                                ButtonSegment(
                                  value: CustomerPhotoType.result,
                                  label: Text('Sonuç'),
                                ),
                              ],
                              selected: {selectedPhotoType},
                              onSelectionChanged: (selection) => setModalState(
                                () => selectedPhotoType = selection.first,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      String? modelId;
                      if (selectedHairstyleName != null) {
                        final matches = HairstyleData.hairstyles.where(
                          (h) => h.name == selectedHairstyleName,
                        );
                        if (matches.isNotEmpty) {
                          modelId = matches.first.id;
                        }
                      }
                      final result = await Navigator.of(context)
                          .push<HairstyleModel>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  HairstyleGallery(selectedId: modelId),
                            ),
                          );
                      if (result != null) {
                        setModalState(() {
                          if (result.id == 'none') {
                            selectedHairstyleName = null;
                          } else {
                            selectedHairstyleName = result.name;
                          }
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.content_cut,
                            color: AppColors.textSecondary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              selectedHairstyleName ??
                                  'Favori Saç Modeli (Opsiyonel)',
                              style: TextStyle(
                                color: selectedHairstyleName != null
                                    ? AppColors.white
                                    : AppColors.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              if (saving || nameController.text.trim().isEmpty)
                                return;
                              setModalState(() => saving = true);
                              try {
                                final newName = nameController.text.trim();
                                final newPhone =
                                    phoneController.text.trim().isEmpty
                                    ? null
                                    : phoneController.text.trim();
                                final newNotes =
                                    notesController.text.trim().isEmpty
                                    ? null
                                    : notesController.text.trim();
                                String? savedPhotoPath = selectedPhotoPath;
                                if (photoChanged && savedPhotoPath != null) {
                                  try {
                                    savedPhotoPath =
                                        await CustomerPhotoStorage.importImage(
                                          savedPhotoPath,
                                        );
                                    uncommittedPhotoPath = savedPhotoPath;
                                  } on FileSystemException catch (_) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        this.context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Fotoğraf kaydedilemedi.',
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                }

                                if (isEditing) {
                                  final updated = Customer(
                                    id: customer.id,
                                    name: newName,
                                    phone: newPhone,
                                    notes: newNotes,
                                    favoriteHairstyle: selectedHairstyleName,
                                    photoPath:
                                        photoChanged && savedPhotoPath == null
                                        ? null
                                        : customer.photoPath,
                                    totalAppointments:
                                        customer.totalAppointments,
                                    lastAppointmentDate:
                                        customer.lastAppointmentDate,
                                    createdAt: customer.createdAt,
                                  );
                                  await _dbService.saveCustomerWithPhoto(
                                    updated,
                                    newPhotoPath: photoChanged
                                        ? savedPhotoPath
                                        : null,
                                    photoType: selectedPhotoType,
                                    photoSource: selectedPhotoSource,
                                  );
                                } else {
                                  await _dbService.saveCustomerWithPhoto(
                                    Customer(
                                      name: newName,
                                      phone: newPhone,
                                      notes: newNotes,
                                      favoriteHairstyle: selectedHairstyleName,
                                    ),
                                    newPhotoPath: savedPhotoPath,
                                    photoType: selectedPhotoType,
                                    photoSource: selectedPhotoSource,
                                  );
                                }
                                uncommittedPhotoPath = null;
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  await _loadCustomers();
                                  if (_searchController.text.isNotEmpty) {
                                    await _searchCustomers(
                                      _searchController.text,
                                    );
                                  }
                                }
                              } catch (_) {
                                if (uncommittedPhotoPath != null) {
                                  await CustomerPhotoStorage.deleteManagedPhoto(
                                    uncommittedPhotoPath,
                                  );
                                  uncommittedPhotoPath = null;
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Müşteri kaydedilemedi. Yeniden deneyin.',
                                      ),
                                    ),
                                  );
                                }
                              } finally {
                                if (context.mounted) {
                                  setModalState(() => saving = false);
                                }
                              }
                            },
                      child: Text(
                        isEditing ? 'GÜNCELLE' : 'KAYDET',
                        style: const TextStyle(
                          color: AppColors.background,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendWhatsAppToCustomer(
    Customer customer, {
    String? customMessage,
  }) async {
    if (customer.phone == null || customer.phone!.isEmpty) {
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
      return;
    }

    final businessName = await WhatsAppService.instance.getBusinessName();
    final message =
        customMessage ??
        'Merhaba ${customer.name} 👋\n\n🏠 *$businessName*\n\nSizi bekliyoruz! 😊';

    final sent = await WhatsAppService.instance.sendWhatsAppMessage(
      phone: customer.phone!,
      message: message,
    );

    if (!sent && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'WhatsApp açılamadı. Lütfen WhatsApp yüklü olduğundan emin olun.',
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

  void _showWhatsAppMessageDialog(Customer customer) {
    final messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.chat, color: Color(0xFF25D366), size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${customer.name} - WhatsApp',
                style: const TextStyle(
                  color: Color(0xFF25D366),
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '📱 ${customer.phone}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: messageController,
                style: const TextStyle(color: AppColors.white, fontSize: 15),
                maxLines: 4,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:
                      'Mesajınızı yazın... (boş bırakırsanız varsayılan mesaj gönderilir)',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Quick templates
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickTemplate('Randevu hatırlatma', Icons.schedule, () {
                  messageController.text =
                      'Merhaba ${customer.name} 👋\n\nRandevunuzu hatırlatmak isteriz. Sizi bekliyoruz! 😊';
                }),
                _buildQuickTemplate('Kampanya', Icons.local_offer, () {
                  messageController.text =
                      'Merhaba ${customer.name} 👋\n\n🎉 Size özel kampanyamız var! Detaylar için bizi ziyaret edin. 💈';
                }),
                _buildQuickTemplate('Tekrar davet', Icons.refresh, () {
                  messageController.text =
                      'Merhaba ${customer.name} 👋\n\nSizi özledik! Yeni bir randevu almak ister misiniz? 😊✂️';
                }),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'İptal',
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
              'WhatsApp Gönder',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              final msg = messageController.text.trim();
              _sendWhatsAppToCustomer(
                customer,
                customMessage: msg.isEmpty ? null : msg,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTemplate(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF25D366).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: const Color(0xFF25D366).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF25D366)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF25D366),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomerDetail(Customer customer) async {
    List<Appointment> appointments = [];
    List<CustomerPhoto> photos = [];
    if (customer.id != null) {
      appointments = await _dbService.getAppointmentsForCustomer(customer.id!);
      photos = await _dbService.getCustomerPhotos(customer.id!);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Customer header
                  Row(
                    children: [
                      _customerAvatar(customer, radius: 30, fontSize: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (customer.phone != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                customer.phone!,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (customer.phone != null) ...[
                        IconButton(
                          onPressed: () => _callCustomer(customer.phone!),
                          icon: const Icon(Icons.phone, color: AppColors.green),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.green.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _showWhatsAppMessageDialog(customer);
                          },
                          icon: const Icon(
                            Icons.chat,
                            color: Color(0xFF25D366),
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(
                              0xFF25D366,
                            ).withValues(alpha: 0.15),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddOrEditCustomerDialog(customer);
                        },
                        icon: const Icon(Icons.edit, color: AppColors.gold),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.gold.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    children: [
                      _buildStat(
                        'Toplam Ziyaret',
                        '${customer.totalAppointments}',
                      ),
                      const SizedBox(width: 16),
                      _buildStat(
                        'Favori Model',
                        customer.favoriteHairstyle ?? '-',
                      ),
                    ],
                  ),

                  if (customer.notes != null &&
                      customer.notes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    CustomerNotesSection(notes: customer.notes!),
                  ],

                  const SizedBox(height: 12),
                  if (photos.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      children: [
                        _photoHistoryChip(
                          'Referans',
                          photos
                              .where(
                                (p) => p.type == CustomerPhotoType.reference,
                              )
                              .length,
                        ),
                        _photoHistoryChip(
                          'Sonuç',
                          photos
                              .where((p) => p.type == CustomerPhotoType.result)
                              .length,
                        ),
                      ],
                    ),

                  const SizedBox(height: 20),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: 12),

                  // Appointment history
                  const Text(
                    'Randevu Geçmişi',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: appointments.isEmpty
                        ? const Center(
                            child: Text(
                              'Henüz randevu yok',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: appointments.length,
                            itemBuilder: (context, index) {
                              final apt = appointments[index];
                              final dateStr = DateFormat(
                                'd MMM yyyy',
                                'tr_TR',
                              ).format(apt.appointmentDate);
                              final isUpcoming =
                                  !apt.isCompleted &&
                                  apt.fullDateTime.isAfter(DateTime.now());
                              return InkWell(
                                onTap: () async {
                                  // Close current dialog
                                  Navigator.pop(context);

                                  // Open edit screen
                                  await Navigator.of(context).push<bool>(
                                    MaterialPageRoute(
                                      builder: (_) => AddAppointmentScreen(
                                        initialDate: apt.appointmentDate,
                                        appointmentToEdit: apt,
                                      ),
                                    ),
                                  );

                                  // Re-open detail if we returned
                                  if (mounted) {
                                    _showCustomerDetail(customer);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(12),
                                    border: isUpcoming
                                        ? Border.all(
                                            color: AppColors.gold.withValues(
                                              alpha: 0.3,
                                            ),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        apt.appointmentTime,
                                        style: const TextStyle(
                                          color: AppColors.gold,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              dateStr,
                                              style: const TextStyle(
                                                color: AppColors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                            if (apt.hairstyleName != null)
                                              Text(
                                                apt.hairstyleName!,
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isUpcoming)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: AppColors.gold,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip:
                                            'Aynı randevuyu tekrar oluştur',
                                        onPressed: () async {
                                          Navigator.pop(context);
                                          await Navigator.of(
                                            this.context,
                                          ).push<bool>(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  AddAppointmentScreen(
                                                    appointmentToRepeat: apt,
                                                  ),
                                            ),
                                          );
                                          if (mounted) {
                                            _showCustomerDetail(customer);
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.repeat,
                                          color: AppColors.gold,
                                          size: 20,
                                        ),
                                      ),
                                      Icon(
                                        apt.isCompleted
                                            ? Icons.check_circle
                                            : Icons.schedule,
                                        color: apt.isCompleted
                                            ? AppColors.green
                                            : AppColors.textSecondary,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _customerAvatar(
    Customer customer, {
    required double radius,
    required double fontSize,
  }) {
    final photoPath = customer.photoPath;
    final initial = customer.name.isEmpty
        ? '?'
        : customer.name[0].toUpperCase();
    if (photoPath != null && photoPath.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.gold.withValues(alpha: 0.15),
        child: ClipOval(
          child: Image.file(
            File(photoPath),
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.gold.withValues(alpha: 0.15),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.gold,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _photoHistoryChip(String label, int count) {
    return Chip(
      avatar: const Icon(Icons.photo_outlined, size: 16, color: AppColors.gold),
      label: Text('$label: $count'),
      backgroundColor: AppColors.background,
      side: const BorderSide(color: AppColors.divider),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
    );
  }

  Widget _buildStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Müşteriler',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOrEditCustomerDialog(),
        backgroundColor: AppColors.gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.person_add, color: AppColors.background),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchCustomers,
                style: const TextStyle(color: AppColors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: AppStrings.searchCustomer,
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _loadCustomers();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          // Customer count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_customers.length} müşteri',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          ),

          // Customer list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold),
                  )
                : _customers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadError ?? AppStrings.noCustomers,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _customers.length,
                    itemBuilder: (context, index) {
                      final customer = _customers[index];
                      return _buildCustomerTile(customer);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerTile(Customer customer) {
    String? subtitle;
    if (customer.lastAppointmentDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final lastD = customer.lastAppointmentDate!;
      final lastDate = DateTime(lastD.year, lastD.month, lastD.day);
      final diff = today.difference(lastDate);

      if (diff.inDays < 0) {
        subtitle = 'Gelecek randevu: ${-diff.inDays} gün sonra';
      } else if (diff.inDays == 0) {
        subtitle = 'Son ziyaret: Bugün';
      } else if (diff.inDays == 1) {
        subtitle = 'Son ziyaret: Dün';
      } else if (diff.inDays < 7) {
        subtitle = 'Son ziyaret: ${diff.inDays} gün önce';
      } else if (diff.inDays < 30) {
        subtitle = 'Son ziyaret: ${(diff.inDays / 7).floor()} hafta önce';
      } else {
        subtitle = 'Son ziyaret: ${(diff.inDays / 30).floor()} ay önce';
      }
    }

    final pendingApt = customer.id != null
        ? _pendingAppointments[customer.id]
        : null;
    Widget? statusWidget;
    if (pendingApt != null) {
      final String dateStr;
      final diff = pendingApt.appointmentDate.difference(DateTime.now());
      if (diff.inDays == 0 &&
          pendingApt.appointmentDate.day == DateTime.now().day) {
        dateStr = 'Bugün';
      } else {
        dateStr = DateFormat(
          'd MMM yyyy',
          'tr_TR',
        ).format(pendingApt.appointmentDate);
      }

      statusWidget = Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 12, color: AppColors.green),
            const SizedBox(width: 4),
            Text(
              'Bekleyen: $dateStr, ${pendingApt.appointmentTime}',
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (subtitle != null) {
      statusWidget = Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }

    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) => _showAddOrEditCustomerDialog(customer),
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
            onPressed: (_) => _deleteCustomer(customer),
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Sil',
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
            ),
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () => _showCustomerDetail(customer),
        onLongPress: () => _deleteCustomer(customer),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _customerAvatar(customer, radius: 24, fontSize: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (customer.phone != null &&
                        customer.phone!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.phone!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    ?statusWidget,
                    if (customer.favoriteHairstyle != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.content_cut,
                            size: 12,
                            color: AppColors.gold.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            customer.favoriteHairstyle!,
                            style: TextStyle(
                              color: AppColors.gold.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // WhatsApp quick send button
              if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _showWhatsAppMessageDialog(customer),
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.chat,
                      color: Color(0xFF25D366),
                      size: 18,
                    ),
                  ),
                ),
              ],
              Column(
                children: [
                  Text(
                    '${customer.totalAppointments}',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'randevu',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerNotesSection extends StatelessWidget {
  const CustomerNotesSection({super.key, required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                color: AppColors.gold,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Müşteri Notu',
                style: TextStyle(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notes,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/whatsapp_service.dart';
import '../utils/constants.dart';

class WhatsAppSettingsScreen extends StatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  State<WhatsAppSettingsScreen> createState() => _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState extends State<WhatsAppSettingsScreen> {
  final _whatsappService = WhatsAppService.instance;
  final _businessNameController = TextEditingController();
  final _customMessageController = TextEditingController();

  bool _autoReminderEnabled = false;
  int _reminderMinutes = WhatsAppService.defaultReminderMinutes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final enabled = await _whatsappService.isAutoReminderEnabled();
    final minutes = await _whatsappService.getReminderMinutes();
    final businessName = await _whatsappService.getBusinessName();
    final customMsg = await _whatsappService.getCustomMessage();

    if (mounted) {
      setState(() {
        _autoReminderEnabled = enabled;
        _reminderMinutes = minutes;
        _businessNameController.text = businessName;
        _customMessageController.text = customMsg;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    await _whatsappService.setAutoReminderEnabled(_autoReminderEnabled);
    await _whatsappService.setReminderMinutes(_reminderMinutes);
    await _whatsappService.setBusinessName(_businessNameController.text.trim());
    await _whatsappService.setCustomMessage(
      _customMessageController.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Ayarlar kaydedildi! ✅',
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

  void _showPreviewDialog() {
    final businessName = _businessNameController.text.trim().isEmpty
        ? 'BarberBook'
        : _businessNameController.text.trim();
    final customMsg = _customMessageController.text.trim();

    String preview =
        'Merhaba Ahmet 👋\n\n'
        '📅 *15/05/2026* tarihinde saat *14:30* için randevunuz bulunmaktadır.\n'
        '✂️ İşlem: *Sakal Tıraşı*\n\n'
        '🏠 *$businessName*\n';

    if (customMsg.isNotEmpty) {
      preview += '\n$customMsg\n';
    }

    preview += '\nSizi bekliyoruz! 😊';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.visibility, color: AppColors.gold, size: 24),
            SizedBox(width: 8),
            Text(
              'Mesaj Önizleme',
              style: TextStyle(
                color: AppColors.gold,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF075E54).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF25D366).withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            preview,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Kapat',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text(
            'WhatsApp Ayarları',
            style: TextStyle(
              color: AppColors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.gold),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'WhatsApp Hatırlatma',
          style: TextStyle(color: AppColors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility, color: AppColors.gold),
            tooltip: 'Mesaj Önizleme',
            onPressed: _showPreviewDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WhatsApp Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF25D366).withValues(alpha: 0.2),
                    const Color(0xFF075E54).withValues(alpha: 0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.chat, color: Color(0xFF25D366), size: 40),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WhatsApp Hatırlatma',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Randevu mesajını hazırlayın ve WhatsApp’ta açın; gönderimi siz tamamlarsınız.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Auto Reminder Toggle
            _buildSectionTitle('Uygulama içi hatırlatma'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Icon(
                    _autoReminderEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off,
                    color: _autoReminderEnabled
                        ? const Color(0xFF25D366)
                        : AppColors.textSecondary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Uygulama içi hatırlatma',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _autoReminderEnabled
                              ? 'Uygulama açıkken randevuya yaklaşınca hatırlatır'
                              : 'Kapalı - Sadece manuel gönderim',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoReminderEnabled,
                    onChanged: (val) {
                      setState(() => _autoReminderEnabled = val);
                    },
                    activeTrackColor: const Color(
                      0xFF25D366,
                    ).withValues(alpha: 0.5),
                    thumbColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return const Color(0xFF25D366);
                      }
                      return AppColors.textSecondary;
                    }),
                    inactiveTrackColor: AppColors.divider,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Reminder Timing
            _buildSectionTitle('Ne Zaman Hatırlatsın?'),
            const SizedBox(height: 8),
            ...WhatsAppService.reminderOptions.map((option) {
              final value = option['value'] as int;
              final label = option['label'] as String;
              final isSelected = _reminderMinutes == value;

              return GestureDetector(
                onTap: () {
                  setState(() => _reminderMinutes = value);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF25D366).withValues(alpha: 0.15)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF25D366).withValues(alpha: 0.5)
                          : AppColors.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? const Color(0xFF25D366)
                            : AppColors.textSecondary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.white
                              : AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      if (isSelected) ...[
                        const Spacer(),
                        const Icon(
                          Icons.check,
                          color: Color(0xFF25D366),
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Business Name
            _buildSectionTitle('Dükkan / İşletme Adı'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _businessNameController,
                style: const TextStyle(color: AppColors.white, fontSize: 16),
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Örn: Ali Usta Kuaför',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                  prefixIcon: const Icon(
                    Icons.store,
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

            const SizedBox(height: 24),

            // Custom Message
            _buildSectionTitle('Ekstra Mesaj (Opsiyonel)'),
            const SizedBox(height: 4),
            const Text(
              'Mesajın sonuna eklenecek ek bilgi (adres, otopark, vb.)',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: TextField(
                controller: _customMessageController,
                style: const TextStyle(color: AppColors.white, fontSize: 16),
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText:
                      'Örn: 📍 Adres: Atatürk Cad. No:15\n🅿️ Otopark mevcuttur.',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: AppColors.gold, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bu hatırlatma uygulama açıkken kontrol edilir; uygulama kapalıyken WhatsApp hatırlatması garanti edilmez. '
                      'Seçtiğinizde WhatsApp hazır mesajla açılır. Gönder düğmesine siz basarsınız; uygulama mesajın gönderildiğini doğrulayamaz.\n\n'
                      'Not: Müşterinin telefon numarası kayıtlı olmalıdır.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save, size: 22),
                label: const Text(
                  'AYARLARI KAYDET',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
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
}

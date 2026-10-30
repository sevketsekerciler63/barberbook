import 'package:flutter/material.dart';
import '../models/hairstyle_template.dart';
import '../services/database_service.dart';
import '../utils/constants.dart';
import '../utils/hairstyle_data.dart';
import '../widgets/hairstyle_card.dart';

class HairstyleGallery extends StatefulWidget {
  final String? selectedId;

  const HairstyleGallery({super.key, this.selectedId});

  @override
  State<HairstyleGallery> createState() => _HairstyleGalleryState();
}

class _HairstyleGalleryState extends State<HairstyleGallery> {
  String? _selectedId;
  List<HairstyleTemplate> _customTemplates = [];

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
    _loadCustomTemplates();
  }

  Future<void> _loadCustomTemplates() async {
    final templates = await DatabaseService.instance.getHairstyleTemplates();
    if (mounted) setState(() => _customTemplates = templates);
  }

  Future<void> _addCustomTemplate() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Özel model ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Berberin tanımladığı model adı',
            hintText: 'Örn. Ali için kısa taper',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Ekle ve seç'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final id = await DatabaseService.instance.insertHairstyleTemplate(
        HairstyleTemplate(name: name),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        HairstyleModel(id: 'custom:$id', name: name, imagePath: ''),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu adla bir özel model zaten var.')),
        );
      }
    }
  }

  void _select(HairstyleModel hairstyle) => Navigator.pop(context, hairstyle);

  @override
  Widget build(BuildContext context) {
    final customModels = _customTemplates
        .map(
          (template) => HairstyleModel(
            id: template.appointmentHairstyleId,
            name: template.name,
            imagePath: '',
          ),
        )
        .toList();
    final models = [...HairstyleData.hairstyles, ...customModels];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Saç Modeli Seç'),
        actions: [
          IconButton(
            tooltip: 'Özel model ekle',
            onPressed: _addCustomTemplate,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.8,
          ),
          itemCount: models.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _choiceCard(
                icon: Icons.not_interested,
                label: 'Belirtilmedi',
                selected: _selectedId == 'none' || _selectedId == null,
                onTap: () => _select(
                  const HairstyleModel(
                    id: 'none',
                    name: 'Belirtilmedi',
                    imagePath: '',
                  ),
                ),
              );
            }
            if (index == 1) {
              return _choiceCard(
                icon: Icons.add,
                label: 'Özel model ekle',
                selected: false,
                onTap: _addCustomTemplate,
              );
            }
            final hairstyle = models[index - 2];
            if (hairstyle.imagePath.isEmpty) {
              return _choiceCard(
                icon: Icons.content_cut,
                label: hairstyle.name,
                selected: _selectedId == hairstyle.id,
                onTap: () => _select(hairstyle),
                subtitle: 'Özel model',
              );
            }
            return HairstyleCard(
              name: hairstyle.name,
              imagePath: hairstyle.imagePath,
              isSelected: _selectedId == hairstyle.id,
              onTap: () => _select(hairstyle),
            );
          },
        ),
      ),
    );
  }

  Widget _choiceCard({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    String? subtitle,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.gold : AppColors.divider,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: selected ? AppColors.gold : AppColors.textSecondary,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? AppColors.gold : AppColors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
        ],
      ),
    ),
  );
}

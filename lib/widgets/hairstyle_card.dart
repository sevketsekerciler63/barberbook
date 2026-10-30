import 'package:flutter/material.dart';
import '../utils/constants.dart';

class HairstyleCard extends StatelessWidget {
  final String name;
  final String imagePath;
  final bool isSelected;
  final VoidCallback onTap;

  const HairstyleCard({
    super.key,
    required this.name,
    required this.imagePath,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: AppColors.surfaceLight,
                          child: Icon(
                            Icons.content_cut,
                            size: 48,
                            color: AppColors.gold.withValues(alpha: 0.5),
                          ),
                        );
                      },
                    ),
                    if (isSelected)
                      Container(
                        color: AppColors.gold.withValues(alpha: 0.2),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle,
                            color: AppColors.gold,
                            size: 40,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Name
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? AppColors.gold : AppColors.white,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

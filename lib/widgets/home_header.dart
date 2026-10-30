import 'package:flutter/material.dart';

import '../utils/constants.dart';

class HomeHeader extends StatelessWidget {
  final Widget managementMenu;
  final bool isSearching;
  final VoidCallback onSearchPressed;
  final bool showTodayButton;
  final VoidCallback onTodayPressed;

  const HomeHeader({
    super.key,
    required this.managementMenu,
    required this.isSearching,
    required this.onSearchPressed,
    required this.showTodayButton,
    required this.onTodayPressed,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useCompactLayout =
              constraints.maxWidth < 360 || textScale > 1.2;

          if (useCompactLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTitle(),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _buildActions(useCompactToday: true),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: _buildTitle()),
              ..._buildActions(useCompactToday: false),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTitle() => const Row(
    children: [
      Icon(Icons.content_cut, color: AppColors.gold, size: 28),
      SizedBox(width: 10),
      Flexible(
        child: Text(
          'BarberBook',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ],
  );

  List<Widget> _buildActions({required bool useCompactToday}) => [
    managementMenu,
    IconButton(
      tooltip: isSearching ? 'Aramayı kapat' : 'Ara',
      icon: Icon(
        isSearching ? Icons.close : Icons.search,
        color: AppColors.gold,
      ),
      onPressed: onSearchPressed,
    ),
    if (showTodayButton)
      if (useCompactToday)
        IconButton.filledTonal(
          tooltip: 'Bugüne dön',
          onPressed: onTodayPressed,
          icon: const Icon(Icons.today),
          color: AppColors.gold,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: AppColors.gold.withValues(alpha: 0.15),
          ),
        )
      else
        TextButton(
          onPressed: onTodayPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.gold,
            backgroundColor: AppColors.gold.withValues(alpha: 0.15),
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Bugün',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
  ];
}

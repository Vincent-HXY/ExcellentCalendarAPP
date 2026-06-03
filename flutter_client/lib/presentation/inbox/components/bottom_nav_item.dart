import 'package:flutter/material.dart';

class BottomNavItemData {
  const BottomNavItemData({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class BottomNavItem extends StatelessWidget {
  const BottomNavItem({
    required this.data,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final BottomNavItemData data;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: data.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF38B9C5) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            data.icon,
            color: isSelected ? Colors.white : const Color(0xFF9AA3A7),
            size: 26,
          ),
        ),
      ),
    );
  }
}

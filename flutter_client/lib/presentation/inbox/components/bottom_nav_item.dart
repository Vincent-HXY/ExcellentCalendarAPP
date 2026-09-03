// 文件作用：底部导航栏的单个图标按钮和导航项数据结构。
// 设计边界：这里只表达图标、选中态和 tooltip，不决定页面切换策略。
import 'package:flutter/material.dart';

class BottomNavItemData {
  const BottomNavItemData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
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
    final colors = Theme.of(context).colorScheme;
    final color = isSelected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: isSelected,
      label: data.label,
      child: Tooltip(
        message: data.label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? data.selectedIcon : data.icon,
                  color: color,
                  size: 25,
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    height: 1,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  child: Text(data.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 文件作用：底部导航栏的单个图标按钮和导航项数据结构。
// 设计边界：这里只表达图标、选中态和 tooltip，不决定页面切换策略。
import 'package:flutter/material.dart';

class BottomNavItemData {
  const BottomNavItemData({required this.icon, required this.label});

  // 数据块作用：导航项图标，用于按钮主体显示。
  final IconData icon;
  // 数据块作用：导航项文字标签，目前主要用于 tooltip 和测试识别。
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
  // 数据块作用：是否为当前选中导航项，决定按钮背景和图标颜色。
  final bool isSelected;
  // 数据块作用：点击导航项时触发的父级回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制单个底部导航图标按钮，并根据选中态切换样式。
    // 关键视觉：选中态使用主强调色填充，未选中态仅显示灰色图标。
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

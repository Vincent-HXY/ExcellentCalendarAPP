// 文件作用：Inbox 底部导航栏，展示当前阶段的五个主入口占位。
// 设计边界：导航项尚未接入路由，后续应由页面状态或路由层统一处理。
import 'package:flutter/material.dart';

import 'bottom_nav_item.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({required this.selectedIndex, super.key});

  // 数据块作用：标记当前选中的底部导航项索引，用于渲染选中态。
  final int selectedIndex;

  // 关键数据：当前标签仍是英文占位，后续应与中文产品导航命名统一。
  // 数据块作用：底部导航的静态配置列表，集中管理图标和可访问性标签。
  static const _items = [
    BottomNavItemData(icon: Icons.inbox_rounded, label: 'Inbox'),
    BottomNavItemData(icon: Icons.calendar_month_rounded, label: 'Calendar'),
    BottomNavItemData(icon: Icons.location_on_rounded, label: 'Location'),
    BottomNavItemData(icon: Icons.search_rounded, label: 'Search'),
    BottomNavItemData(icon: Icons.more_horiz_rounded, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    // 函数作用：把导航项配置渲染成横向底部导航栏。
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var index = 0; index < _items.length; index++)
            BottomNavItem(
              data: _items[index],
              isSelected: index == selectedIndex,
              onTap: () {},
            ),
        ],
      ),
    );
  }
}

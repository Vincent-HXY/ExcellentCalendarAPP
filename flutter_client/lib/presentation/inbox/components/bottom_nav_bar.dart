import 'package:flutter/material.dart';

import 'bottom_nav_item.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    BottomNavItemData(
      icon: Icons.view_agenda_outlined,
      selectedIcon: Icons.view_agenda_rounded,
      label: '日程',
    ),
    BottomNavItemData(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
      label: '日历',
    ),
    BottomNavItemData(
      icon: Icons.search_rounded,
      selectedIcon: Icons.manage_search_rounded,
      label: '搜索',
    ),
    BottomNavItemData(
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x0D111827))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0D111827),
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: BottomNavItem(
                    data: _items[index],
                    isSelected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

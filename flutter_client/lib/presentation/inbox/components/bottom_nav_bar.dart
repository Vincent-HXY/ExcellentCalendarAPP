import 'package:flutter/material.dart';

import 'bottom_nav_item.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({required this.selectedIndex, super.key});

  final int selectedIndex;

  static const _items = [
    BottomNavItemData(icon: Icons.inbox_rounded, label: 'Inbox'),
    BottomNavItemData(icon: Icons.calendar_month_rounded, label: 'Calendar'),
    BottomNavItemData(icon: Icons.location_on_rounded, label: 'Location'),
    BottomNavItemData(icon: Icons.search_rounded, label: 'Search'),
    BottomNavItemData(icon: Icons.more_horiz_rounded, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
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

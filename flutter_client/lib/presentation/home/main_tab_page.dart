import 'package:flutter/material.dart';

import '../inbox/components/bottom_nav_bar.dart';

typedef MainTabBuilder = Widget Function(BuildContext context);

class MainTabPage extends StatefulWidget {
  const MainTabPage({
    required this.scheduleBuilder,
    required this.profileBuilder,
    super.key,
  });

  final MainTabBuilder scheduleBuilder;
  final MainTabBuilder profileBuilder;

  @override
  State<MainTabPage> createState() => _MainTabPageState();
}

class _MainTabPageState extends State<MainTabPage> {
  static const _tabCount = 4;

  final List<Widget?> _pages = List<Widget?>.filled(_tabCount, null);
  int _selectedIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pages[0] ??= widget.scheduleBuilder(context);
  }

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    _pages[index] ??= switch (index) {
      1 => const DevelopmentPlaceholderPage(
        icon: Icons.calendar_month_outlined,
        title: '日历板块正在开发中',
      ),
      2 => const DevelopmentPlaceholderPage(
        icon: Icons.search_rounded,
        title: '搜索板块正在开发中',
      ),
      3 => widget.profileBuilder(context),
      _ => widget.scheduleBuilder(context),
    };
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          for (var index = 0; index < _tabCount; index++)
            _pages[index] ?? const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavBar(
        selectedIndex: _selectedIndex,
        onSelected: _selectTab,
      ),
    );
  }
}

class DevelopmentPlaceholderPage extends StatelessWidget {
  const DevelopmentPlaceholderPage({
    required this.icon,
    required this.title,
    super.key,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE6F8FA),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: const Color(0xFF24AFC0)),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF263238),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '我们正在完善这个功能，敬请期待',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF7A878D), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

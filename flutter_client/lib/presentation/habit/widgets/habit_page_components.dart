import 'package:flutter/material.dart';

import '../habit_design.dart';

class HabitPageScaffold extends StatelessWidget {
  const HabitPageScaffold({
    required this.title,
    required this.body,
    this.leading,
    this.actions,
    super.key,
  });

  final String title;
  final Widget body;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Theme(
    data: HabitDesign.pageTheme(context),
    child: Scaffold(
      backgroundColor: HabitDesign.background(context),
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(title),
        leading: leading,
        actions: [...?actions, const SizedBox(width: 12)],
      ),
      body: SafeArea(top: false, child: body),
    ),
  );
}

class HabitSectionCard extends StatelessWidget {
  const HabitSectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: HabitDesign.cardDecoration(context),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(HabitDesign.radius),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class HabitSectionHeading extends StatelessWidget {
  const HabitSectionHeading({
    required this.title,
    required this.icon,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HabitIconBadge(icon: icon, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: HabitDesign.muted(context),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class HabitIconBadge extends StatelessWidget {
  const HabitIconBadge({required this.icon, this.size = 44, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: HabitDesign.tint(context),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(
      icon,
      size: size * 0.52,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class HabitLabel extends StatelessWidget {
  const HabitLabel({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: HabitDesign.tint(context),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class HabitDialog extends StatelessWidget {
  const HabitDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Theme(
    data: HabitDesign.pageTheme(context),
    child: AlertDialog(title: title, content: content, actions: actions),
  );
}

class HabitEmptyState extends StatelessWidget {
  const HabitEmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.spa_outlined,
    this.action,
    this.actionLabel = '重试',
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? action;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HabitIconBadge(icon: icon, size: 76),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: HabitDesign.muted(context), height: 1.7),
          ),
          if (action != null) ...[
            const SizedBox(height: 24),
            FilledButton(onPressed: action, child: Text(actionLabel)),
          ],
        ],
      ),
    ),
  );
}

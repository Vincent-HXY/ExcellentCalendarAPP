import 'package:flutter/material.dart';

import '../search_design_tokens.dart';

class SearchLoadingSkeleton extends StatelessWidget {
  const SearchLoadingSkeleton({super.key});
  @override
  Widget build(BuildContext context) {
    final palette = SearchPalette.of(context);
    return Semantics(
      label: '正在搜索',
      liveRegion: true,
      child: Column(
        children: List.generate(
          3,
          (index) => Container(
            height: 132,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(
                SearchDesignTokens.cardRadius,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SearchMessageState extends StatelessWidget {
  const SearchMessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 58, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 46, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

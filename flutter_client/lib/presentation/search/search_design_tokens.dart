import 'package:flutter/material.dart';

import '../app_design_tokens.dart';

@immutable
class SearchPalette {
  const SearchPalette({
    required this.background,
    required this.searchField,
    required this.card,
    required this.historyChip,
    required this.historyChipOutline,
    required this.historyChipForeground,
    required this.outline,
    required this.divider,
    required this.shadow,
  });

  factory SearchPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final light = scheme.brightness == Brightness.light;
    return SearchPalette(
      background: light ? AppColors.lightPageBackground : scheme.surface,
      searchField: light ? Colors.white : scheme.surfaceContainerHigh,
      card: light ? Colors.white : scheme.surfaceContainerLow,
      historyChip: light
          ? const Color(0xFFEAF4FF)
          : Color.alphaBlend(
              const Color(0x293B82F6),
              scheme.surfaceContainerLow,
            ),
      historyChipOutline: light
          ? const Color(0xFFC8DDF8)
          : const Color(0x996FA8F8),
      historyChipForeground: light
          ? const Color(0xFF3979D8)
          : const Color(0xFF8BB8FF),
      outline: scheme.outlineVariant.withValues(alpha: light ? 0.42 : 0.72),
      divider: scheme.outlineVariant.withValues(alpha: light ? 0.48 : 0.64),
      shadow: light
          ? const Color(0x1A23444A)
          : Colors.black.withValues(alpha: 0.24),
    );
  }

  final Color background;
  final Color searchField;
  final Color card;
  final Color historyChip;
  final Color historyChipOutline;
  final Color historyChipForeground;
  final Color outline;
  final Color divider;
  final Color shadow;

  Color sectionColor(ColorScheme scheme, int index) {
    final anchor = switch (index) {
      0 => const Color(0xFF3B82F6),
      1 => const Color(0xFF45A861),
      _ => const Color(0xFFF05D82),
    };
    final hsl = HSLColor.fromColor(Color.lerp(anchor, scheme.primary, 0.08)!);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.52, 0.82))
        .withLightness(
          scheme.brightness == Brightness.dark
              ? hsl.lightness.clamp(0.62, 0.74)
              : hsl.lightness.clamp(0.44, 0.58),
        )
        .toColor();
  }
}

abstract final class SearchDesignTokens {
  static const contentMaxWidth = 720.0;
  static const pagePadding = 20.0;
  static const compactPagePadding = 18.0;
  static const searchRadius = 28.0;
  static const cardRadius = 18.0;
  static const popoverRadius = 26.0;
  static const searchHeight = 56.0;
  static const minimumTouchTarget = 48.0;
  static const titleScale = 0.75;
  static const historyChipHeight = 28.0;
  static const historyChipFontSize = 12.0;
  static const headerMotionMilliseconds = 300;
  static const resultTitleScale = 0.875;
  static const resultRowVerticalPadding = 10.0;
  static const resultContentIndent = 64.0;
  static const resultRightPadding = 14.0;
  static const resultContentGap = 4.0;
  static const resultStatusGap = 5.0;
  static const loadMoreRowHeight = 40.0;

  static Duration motion(BuildContext context, int milliseconds) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  static ({Color background, Color foreground}) highlightColors(
    ColorScheme colors,
    Color accentColor,
  ) {
    final background = Color.alphaBlend(
      accentColor.withValues(
        alpha: colors.brightness == Brightness.dark ? 0.24 : 0.16,
      ),
      colors.surfaceContainerHigh,
    );
    return (background: background, foreground: accentColor);
  }
}

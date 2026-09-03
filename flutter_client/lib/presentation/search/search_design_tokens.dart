import 'package:flutter/material.dart';

abstract final class SearchDesignTokens {
  static const contentMaxWidth = 720.0;
  static const pagePadding = 20.0;
  static const compactPagePadding = 18.0;
  static const searchRadius = 24.0;
  static const cardRadius = 22.0;
  static const popoverRadius = 26.0;
  static const searchHeight = 56.0;
  static const minimumTouchTarget = 48.0;

  static Duration motion(BuildContext context, int milliseconds) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  static Color sectionColor(ColorScheme colors, int index) => switch (index) {
    0 => colors.primary,
    1 => colors.tertiary,
    _ => colors.error,
  };

  static ({Color background, Color foreground}) highlightColors(
    ColorScheme colors,
  ) {
    final background = colors.brightness == Brightness.dark
        ? Color.alphaBlend(const Color(0x667B5D00), colors.surfaceContainerHigh)
        : Color.alphaBlend(
            const Color(0x66FFD54F),
            colors.surfaceContainerHigh,
          );
    return (background: background, foreground: colors.onSurface);
  }
}

import 'package:flutter/material.dart';

import '../app_design_tokens.dart';

@immutable
class CalendarPalette {
  const CalendarPalette({
    required this.background,
    required this.panel,
    required this.card,
    required this.outline,
    required this.event,
    required this.eventContainer,
    required this.habit,
    required this.habitContainer,
    required this.anniversary,
    required this.anniversaryContainer,
    required this.mutedText,
  });

  factory CalendarPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final event = _semanticColor(scheme, const Color(0xFF3979D8), brightness);
    final habit = _semanticColor(scheme, const Color(0xFF2E9B65), brightness);
    final anniversary = _semanticColor(
      scheme,
      const Color(0xFFE27B35),
      brightness,
    );
    return CalendarPalette(
      background: brightness == Brightness.light
          ? AppColors.lightPageBackground
          : scheme.surface,
      panel: scheme.surfaceContainerLow,
      card: scheme.surfaceContainerLowest,
      outline: scheme.outlineVariant.withValues(alpha: 0.72),
      event: event,
      eventContainer: Color.alphaBlend(
        event.withValues(alpha: brightness == Brightness.dark ? 0.18 : 0.10),
        scheme.surfaceContainerLowest,
      ),
      habit: habit,
      habitContainer: Color.alphaBlend(
        habit.withValues(alpha: brightness == Brightness.dark ? 0.18 : 0.10),
        scheme.surfaceContainerLowest,
      ),
      anniversary: anniversary,
      anniversaryContainer: Color.alphaBlend(
        anniversary.withValues(
          alpha: brightness == Brightness.dark ? 0.18 : 0.10,
        ),
        scheme.surfaceContainerLowest,
      ),
      mutedText: scheme.onSurfaceVariant,
    );
  }

  final Color background;
  final Color panel;
  final Color card;
  final Color outline;
  final Color event;
  final Color eventContainer;
  final Color habit;
  final Color habitContainer;
  final Color anniversary;
  final Color anniversaryContainer;
  final Color mutedText;

  static Color _semanticColor(
    ColorScheme scheme,
    Color anchor,
    Brightness brightness,
  ) {
    final mixed = Color.lerp(anchor, scheme.primary, 0.18)!;
    final hsl = HSLColor.fromColor(mixed);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.48, 0.78))
        .withLightness(
          brightness == Brightness.dark
              ? hsl.lightness.clamp(0.60, 0.72)
              : hsl.lightness.clamp(0.42, 0.56),
        )
        .toColor();
  }
}

abstract final class CalendarSpacing {
  static const pageHorizontal = 16.0;
  static const compactPageHorizontal = 8.0;
  static const sectionGap = 18.0;
  static const cardGap = 10.0;
  static const contentBottom = 112.0;
}

abstract final class CalendarRadius {
  static const panel = 22.0;
  static const card = 18.0;
  static const chip = 999.0;
}

abstract final class CalendarMotion {
  static const selection = Duration(milliseconds: 160);
  static const page = Duration(milliseconds: 240);
  static const collapse = Duration(milliseconds: 260);
  static const panel = Duration(milliseconds: 220);
  static const section = Duration(milliseconds: 180);

  static const enter = Curves.easeOutCubic;
  static const standard = Curves.easeInOutCubic;

  static bool isReduced(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  static Duration effective(BuildContext context, Duration duration) =>
      isReduced(context) ? Duration.zero : duration;
}

double calendarPageHorizontalPadding(double width) => width <= 380
    ? CalendarSpacing.compactPageHorizontal
    : CalendarSpacing.pageHorizontal;

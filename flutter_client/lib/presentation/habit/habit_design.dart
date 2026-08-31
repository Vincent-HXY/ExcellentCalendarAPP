import 'package:flutter/material.dart';

abstract final class HabitDesign {
  static const radius = 20.0;

  static Color background(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerLow;
  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color danger(BuildContext context) =>
      Theme.of(context).colorScheme.error;
}

ThemeData buildHabitAppTheme({
  required Color seedColor,
  required Brightness brightness,
}) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  ),
  fontFamily: 'Roboto',
  useMaterial3: true,
);

String formatHabitDate(String value) {
  final date = DateTime.parse(value);
  return '${date.year}年${date.month}月${date.day}日';
}

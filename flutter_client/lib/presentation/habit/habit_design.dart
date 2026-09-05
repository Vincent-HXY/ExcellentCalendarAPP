import 'package:flutter/material.dart';

import '../../native_contract/habit/habit_contract_enums.dart';
import '../app_design_tokens.dart';

abstract final class HabitDesign {
  static const radius = 22.0;

  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? AppColors.lightPageBackground
      : Theme.of(context).colorScheme.surface;
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
      ? Colors.white
      : Theme.of(context).colorScheme.surfaceContainerLow;
  static Color text(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color danger(BuildContext context) =>
      Theme.of(context).colorScheme.error;

  static Color tint(BuildContext context) => Color.alphaBlend(
    Theme.of(context).colorScheme.primary.withValues(
      alpha: Theme.of(context).brightness == Brightness.light ? 0.07 : 0.15,
    ),
    surface(context),
  );

  static Color outline(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35);

  static BoxDecoration cardDecoration(BuildContext context) => BoxDecoration(
    color: surface(context),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: outline(context)),
    boxShadow: Theme.of(context).brightness == Brightness.light
        ? const [
            BoxShadow(
              color: Color(0x070B4850),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ]
        : null,
  );

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations == true ||
      MediaQuery.maybeOf(context)?.accessibleNavigation == true;

  // Applied inside Habit routes only; the app-wide appearance seed stays intact.
  static ThemeData pageTheme(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    return theme.copyWith(
      scaffoldBackgroundColor: background(context),
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: background(context),
        foregroundColor: text(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: text(context),
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: shape,
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          side: BorderSide(color: outline(context)),
          backgroundColor: surface(context),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: tint(context),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      chipTheme: theme.chipTheme.copyWith(
        backgroundColor: tint(context),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      dividerTheme: DividerThemeData(color: outline(context), space: 1),
      dialogTheme: theme.dialogTheme.copyWith(
        backgroundColor: surface(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
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

String habitDayStatusLabel(HabitDailyStatusContract status) => switch (status) {
  HabitDailyStatusContract.upcoming => '尚未开始',
  HabitDailyStatusContract.absent => '待完成',
  HabitDailyStatusContract.partial => '进行中',
  HabitDailyStatusContract.done => '已完成',
  HabitDailyStatusContract.skipped => '已跳过',
  HabitDailyStatusContract.missed => '未完成',
};

IconData habitDayStatusIcon(HabitDailyStatusContract status) =>
    switch (status) {
      HabitDailyStatusContract.done => Icons.check_rounded,
      HabitDailyStatusContract.partial => Icons.timelapse_rounded,
      HabitDailyStatusContract.skipped => Icons.remove_rounded,
      HabitDailyStatusContract.missed => Icons.close_rounded,
      HabitDailyStatusContract.absent => Icons.radio_button_unchecked_rounded,
      HabitDailyStatusContract.upcoming => Icons.schedule_rounded,
    };

String habitLifecycleLabel(HabitLifecycleStatusContract status) =>
    switch (status) {
      HabitLifecycleStatusContract.active => '进行中',
      HabitLifecycleStatusContract.upcoming => '即将开始',
      HabitLifecycleStatusContract.completed => '已结束',
      HabitLifecycleStatusContract.endedEarly => '提前结束',
    };

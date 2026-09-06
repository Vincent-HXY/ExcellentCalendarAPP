import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';
import '../../native_contract/appearance/display_preferences.dart';

String? displayFontName(DisplayFontFamily family) => switch (family) {
  DisplayFontFamily.system => null,
  DisplayFontFamily.notoSansSc => 'CalendarSansSC',
  DisplayFontFamily.notoSerifSc => 'CalendarSerifSC',
};

class AppTypography extends InheritedWidget {
  const AppTypography({required this.preferences, required super.child, super.key});
  final DisplayPreferences preferences;

  static TextStyle resolve(BuildContext context, TextStyle? style) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppTypography>();
    final base = DefaultTextStyle.of(context).style.merge(style);
    if (scope == null) return base;
    final weight = FontWeight.values[((base.fontWeight ?? FontWeight.w400).index + scope.preferences.fontWeightDelta).clamp(0, 8)];
    return base.copyWith(
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
    );
  }

  @override
  bool updateShouldNotify(AppTypography oldWidget) => preferences != oldWidget.preferences;
}

/// Keeps explicit page styles responsive to the user's weight preference.
/// Flutter Theme alone cannot override a TextStyle's explicit fontWeight.
class AppText extends StatelessWidget {
  const AppText(this.data, {super.key, this.style, this.strutStyle, this.textAlign, this.textDirection, this.locale, this.softWrap, this.overflow, this.textScaler, this.maxLines, this.semanticsLabel, this.semanticsIdentifier, this.textWidthBasis, this.textHeightBehavior, this.selectionColor});
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final String? semanticsIdentifier;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => Text(data,
    style: AppTypography.resolve(context, style), strutStyle: strutStyle,
    textAlign: textAlign, textDirection: textDirection, locale: locale,
    softWrap: softWrap, overflow: overflow, textScaler: textScaler, maxLines: maxLines,
    semanticsLabel: semanticsLabel, semanticsIdentifier: semanticsIdentifier,
    textWidthBasis: textWidthBasis, textHeightBehavior: textHeightBehavior, selectionColor: selectionColor,
  );
}

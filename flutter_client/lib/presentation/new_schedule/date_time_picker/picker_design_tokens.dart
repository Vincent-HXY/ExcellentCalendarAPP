import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../new_schedule_design_tokens.dart';

class PickerColors {
  const PickerColors._();

  static const surface = NewScheduleColors.surface;
  static const primary = NewScheduleColors.accent;
  static const textPrimary = NewScheduleColors.body;
  static const textSecondary = NewScheduleColors.muted;
  static const textDisabled = Color(0xFFC5C8CB);
  static const divider = NewScheduleColors.divider;
  static const controlBackground = Color(0xFFF1F3F4);
  static const switchOff = NewScheduleColors.switchOff;
}

class PickerSpacing {
  const PickerSpacing._();

  static const sheetHorizontal = 24.0;
  static const rowGap = 12.0;
  static const sectionGap = 16.0;
}

class PickerSizes {
  const PickerSizes._();

  static const sheetRadius = AppRadius.formCard;
  static const valueRowHeight = 52.0;
  static const capsuleTapHeight = 48.0;
  static const capsuleVisualHeight = 40.0;
  static const capsuleHorizontalPadding = 18.0;
  static const dayCellExtent = 42.0;
  static const dayCircle = 38.0;
  static const wheelItemExtent = 52.0;
  static const wheelHeight = 186.0;
  static const bottomActionHeight = 56.0;
}

class PickerTextStyles {
  const PickerTextStyles._();

  static const title = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const label = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const pill = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const calendarMonth = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const week = TextStyle(
    color: PickerColors.textSecondary,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const day = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const wheelSelected = TextStyle(
    color: PickerColors.textPrimary,
    fontSize: 26,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const wheelUnselected = TextStyle(
    color: PickerColors.textDisabled,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const action = TextStyle(
    color: PickerColors.primary,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1,
  );
}

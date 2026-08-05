import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import 'schedule_date_time_picker_sheet.dart';

enum PickerInitialStep { calendar, time, yearMonthDay }

enum PickerTarget { start, end }

enum CalendarSystem { gregorian, lunar }

enum DateTimePickerStep { calendar, time, yearMonthDay }

class ScheduleDateTimeSelection {
  const ScheduleDateTimeSelection({
    required this.localDateTime,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.timezone,
    required this.calendarSystem,
  });

  final DateTime localDateTime;
  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final String timezone;
  final CalendarSystem calendarSystem;
}

class CalendarDateValue {
  const CalendarDateValue({
    required this.year,
    required this.month,
    required this.day,
    required this.system,
  });

  final int year;
  final int month;
  final int day;
  final CalendarSystem system;
}

abstract interface class CalendarDateAdapter {
  DateTime toGregorian(CalendarDateValue value);
  CalendarDateValue fromGregorian(DateTime value);
}

class GregorianCalendarDateAdapter implements CalendarDateAdapter {
  const GregorianCalendarDateAdapter();

  @override
  CalendarDateValue fromGregorian(DateTime value) {
    return CalendarDateValue(
      year: value.year,
      month: value.month,
      day: value.day,
      system: CalendarSystem.gregorian,
    );
  }

  @override
  DateTime toGregorian(CalendarDateValue value) {
    return DateTime(value.year, value.month, value.day);
  }
}

Future<ScheduleDateTimeSelection?> showScheduleDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  required String timezone,
  PickerInitialStep initialStep = PickerInitialStep.calendar,
  PickerTarget target = PickerTarget.start,
}) {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);

  return showModalBottomSheet<ScheduleDateTimeSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    sheetAnimationStyle: AnimationStyle(
      duration: disableAnimations ? Duration.zero : AppMotion.pickerSheet,
      reverseDuration: disableAnimations
          ? Duration.zero
          : AppMotion.pickerSheet,
      curve: AppMotion.enter,
      reverseCurve: AppMotion.standard,
    ),
    builder: (context) {
      final viewInsets = MediaQuery.viewInsetsOf(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
        child: ScheduleDateTimePickerSheet(
          initialDateTime: initialDateTime,
          timezone: timezone,
          target: target,
          initialStep: switch (initialStep) {
            PickerInitialStep.calendar => DateTimePickerStep.calendar,
            PickerInitialStep.time => DateTimePickerStep.time,
            PickerInitialStep.yearMonthDay => DateTimePickerStep.yearMonthDay,
          },
        ),
      );
    },
  );
}

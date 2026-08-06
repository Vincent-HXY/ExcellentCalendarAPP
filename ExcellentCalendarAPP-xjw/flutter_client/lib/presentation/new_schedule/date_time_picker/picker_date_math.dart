import 'package:flutter/material.dart';

abstract final class PickerDateMath {
  static const yearRangePadding = 100;

  static int clampedDay({
    required int year,
    required int month,
    required int day,
  }) {
    return day.clamp(1, DateUtils.getDaysInMonth(year, month));
  }

  static DateTime clampedDate({
    required int year,
    required int month,
    required int day,
  }) {
    return DateTime(
      year,
      month,
      clampedDay(year: year, month: month, day: day),
    );
  }

  static DateTime shiftMonth(DateTime month, int delta) {
    return DateTime(month.year, month.month + delta);
  }
}

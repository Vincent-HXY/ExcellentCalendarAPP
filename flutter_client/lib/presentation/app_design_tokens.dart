import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const segmentedControl = Duration(milliseconds: 280);
  static const sectionExpand = Duration(milliseconds: 420);
  static const sectionCollapse = Duration(milliseconds: 320);
  static const arrowRotation = Duration(milliseconds: 260);
  static const fabPress = Duration(milliseconds: 90);
  static const fabRelease = Duration(milliseconds: 120);
  static const routeEnter = Duration(milliseconds: 280);
  static const routeExit = Duration(milliseconds: 220);
  static const fabPostReleasePause = Duration(milliseconds: 40);
  static const pickerSheet = Duration(milliseconds: 300);
  static const pickerMonth = Duration(milliseconds: 280);
  static const pickerPanel = Duration(milliseconds: 320);
  static const pickerYearMonthDayPanel = Duration(milliseconds: 300);
  static const pickerDaySelection = Duration(milliseconds: 180);
  static const pickerAutoStepPause = Duration(milliseconds: 100);

  static const standard = Curves.easeInOutCubic;
  static const enter = Curves.easeOutCubic;
  static const press = Curves.easeOut;
  static const release = Curves.easeOutBack;
}

abstract final class AppRadius {
  static const sectionCard = 14.0;
  static const formCard = 14.0;
}

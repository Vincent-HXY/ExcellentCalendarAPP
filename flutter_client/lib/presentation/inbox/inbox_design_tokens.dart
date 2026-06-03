import 'package:flutter/material.dart';

class InboxColors {
  const InboxColors._();

  static const pageBackground = Color(0xFFE6F8FA);
  static const surface = Colors.white;
  static const title = Color(0xFF111518);
  static const body = Color(0xFF1C2326);
  static const mutedText = Color(0xFF9AA3A7);
  static const divider = Color(0xFFF1F3F4);
  static const dueDate = Color(0xFF8F2D2F);
  static const checkbox = Color(0xFFC5CCD0);
  static const checkboxImportant = Color(0xFFE15E64);
  static const accent = Color(0xFF38B9C5);
}

class InboxSpacing {
  const InboxSpacing._();

  static const pageHorizontal = 28.0;
  static const cardTop = 8.0;
  static const contentBottom = 104.0;
  static const cardVerticalPadding = 10.0;
  static const rowHorizontal = 22.0;
  static const checkboxGap = 14.0;
  static const dateGap = 10.0;
}

class InboxSizes {
  const InboxSizes._();

  static const topBarHeight = 76.0;
  static const topBarIconButton = 40.0;
  static const topBarIcon = 26.0;
  static const rowHeight = 46.0;
  static const cardRadius = 30.0;
  static const checkbox = 22.0;
  static const checkboxBorder = 2.0;
  static const checkIcon = 15.0;
  static const dateMaxWidth = 58.0;
}

class InboxTextStyles {
  const InboxTextStyles._();

  static const headerTitle = TextStyle(
    color: InboxColors.title,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1,
  );

  static const taskTitle = TextStyle(
    color: InboxColors.body,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );

  static const dueDate = TextStyle(
    color: InboxColors.dueDate,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.1,
  );
}

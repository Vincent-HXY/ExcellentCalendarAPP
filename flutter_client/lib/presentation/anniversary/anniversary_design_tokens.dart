import 'package:flutter/material.dart';

abstract final class AnniversaryColors {
  static const listBackground = Color(0xFFE8F7FA);
  static const detailBackground = Color(0xFFD2EAEE);
  static const primaryTeal = Color(0xFF62BDCB);
  static const elapsedGreen = Color(0xFF16C99B);
  static const primaryText = Color(0xFF1D2023);
  static const secondaryText = Color(0xFF7A888B);
  static const cardBackground = Colors.white;
  static const selectedChip = Color(0xFFE0F4F6);
  static const divider = Color(0xFFEAF0F1);
  static const error = Color(0xFFC43D4E);

  static const iconBlue = Color(0xFFDCECFB);
  static const iconBlueForeground = Color(0xFF4B89C7);
  static const iconAqua = Color(0xFFD8F4F2);
  static const iconAquaForeground = Color(0xFF35A9A5);
  static const iconOrange = Color(0xFFFFE9D8);
  static const iconOrangeForeground = Color(0xFFE88340);
  static const iconGreen = Color(0xFFDFF5E8);
  static const iconGreenForeground = Color(0xFF4FA975);

  static const themeMint = Color(0xFF62BDCB);
  static const themeLavender = Color(0xFF9A96D8);
  static const themePeach = Color(0xFFEAA783);
}

abstract final class AnniversarySpacing {
  static const pageHorizontal = 20.0;
  static const listGap = 15.0;
  static const sectionGap = 16.0;
  static const formBottom = 32.0;
}

abstract final class AnniversarySizes {
  static const listCardRadius = 24.0;
  static const formCardRadius = 22.0;
  static const iconCircle = 48.0;
  static const minTapTarget = 48.0;
  static const detailCardMaxWidth = 380.0;
}

abstract final class AnniversaryShadows {
  static const card = [
    BoxShadow(color: Color(0x100B4850), blurRadius: 18, offset: Offset(0, 7)),
  ];
}

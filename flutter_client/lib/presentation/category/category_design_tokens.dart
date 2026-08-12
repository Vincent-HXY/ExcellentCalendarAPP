import 'package:flutter/material.dart';

class CategoryColors {
  const CategoryColors._();

  static const pageBackground = Color(0xFFF0F1F3);
  static const surface = Colors.white;
  static const accent = Color(0xFF3ED4D5);
  static const primaryText = Color(0xFF111416);
  static const secondaryText = Color(0xFF979EA1);
  static const selectionIdle = Color(0xFFD1D6D9);
  static const error = Color(0xFFB3261E);
}

class CategorySpacing {
  const CategorySpacing._();

  static const pageHorizontal = 20.0;
  static const cardHorizontal = 22.0;
  static const cardGap = 12.0;
  static const sectionGap = 16.0;
  static const bottom = 28.0;
}

class CategorySizes {
  const CategorySizes._();

  static const topBarHeight = 72.0;
  static const minTapTarget = 48.0;
  static const cardRadius = 18.0;
  static const listCardMinHeight = 70.0;
  static const colorTapTarget = 48.0;
}

class CategoryColorOption {
  const CategoryColorOption({
    required this.label,
    required this.hex,
    required this.color,
  });

  final String label;
  final String hex;
  final Color color;
}

const categoryColorOptions = <CategoryColorOption>[
  CategoryColorOption(label: '蓝色', hex: '#5C93E5', color: Color(0xFF5C93E5)),
  CategoryColorOption(label: '青色', hex: '#39AFBD', color: Color(0xFF39AFBD)),
  CategoryColorOption(label: '绿色', hex: '#4ABD56', color: Color(0xFF4ABD56)),
  CategoryColorOption(label: '黄色', hex: '#E4AF2D', color: Color(0xFFE4AF2D)),
  CategoryColorOption(label: '橙色', hex: '#E58F44', color: Color(0xFFE58F44)),
  CategoryColorOption(label: '红色', hex: '#E56F65', color: Color(0xFFE56F65)),
  CategoryColorOption(label: '紫色', hex: '#B874E5', color: Color(0xFFB874E5)),
];

Color categoryColorFromHex(String? value) {
  if (value == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) {
    return CategoryColors.selectionIdle;
  }
  return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
}

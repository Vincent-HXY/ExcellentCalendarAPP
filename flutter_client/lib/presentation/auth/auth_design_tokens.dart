import 'package:flutter/material.dart';

/// Shared visual tokens for the authentication pages, kept consistent with
/// the app-wide seed color.
abstract final class AuthDesignTokens {
  static const Color pageBackground = Color(0xFFE6F8FA);
  static const Color cardBackground = Colors.white;
  static const Color primary = Color(0xFF38B9C5);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color error = Color(0xFFB3261E);

  static const TextStyle pageTitleStyle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: textPrimary,
  );
  static const TextStyle fieldLabelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: textSecondary,
  );
  static const TextStyle errorTextStyle = TextStyle(
    fontSize: 12.5,
    color: error,
  );
  static const TextStyle hintTextStyle = TextStyle(
    fontSize: 13,
    color: textMuted,
  );
}

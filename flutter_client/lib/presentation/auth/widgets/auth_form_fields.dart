import 'package:flutter/material.dart';

import '../auth_design_tokens.dart';

/// Reusable labeled text field with inline error support.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    required this.label,
    required this.controller,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLength,
    this.suffix,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final Widget? suffix;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AuthDesignTokens.fieldLabelStyle),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          maxLength: maxLength,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: const TextStyle(
            fontSize: 15,
            color: AuthDesignTokens.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AuthDesignTokens.cardBackground,
            counterText: '',
            hintStyle: AuthDesignTokens.hintTextStyle,
            suffixIcon: suffix,
            errorText: errorText,
            errorStyle: AuthDesignTokens.errorTextStyle,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AuthDesignTokens.primary,
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AuthDesignTokens.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AuthDesignTokens.error,
                width: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Password visibility toggle suffix icon.
class ObscureToggle extends StatelessWidget {
  const ObscureToggle({
    required this.obscure,
    required this.onPressed,
    super.key,
  });

  final bool obscure;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscure ? '显示密码' : '隐藏密码',
      onPressed: onPressed,
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
        color: AuthDesignTokens.textMuted,
      ),
    );
  }
}

/// Banner for page-level (non-field) errors.
class AuthFormErrorBanner extends StatelessWidget {
  const AuthFormErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AuthDesignTokens.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AuthDesignTokens.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AuthDesignTokens.errorTextStyle.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Info banner for success hints (e.g. the forgot-password unified copy).
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AuthDesignTokens.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: Color(0xFF0E7490),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0E7490)),
            ),
          ),
        ],
      ),
    );
  }
}

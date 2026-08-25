import 'package:flutter/material.dart';

import '../../auth/auth_design_tokens.dart';

/// A single label/value row used by the profile page.
class ProfileInfoRow extends StatelessWidget {
  const ProfileInfoRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AuthDesignTokens.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: AuthDesignTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

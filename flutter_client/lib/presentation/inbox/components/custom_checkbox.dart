import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';

class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({
    required this.isChecked,
    required this.isImportant,
    super.key,
  });

  final bool isChecked;
  final bool isImportant;

  @override
  Widget build(BuildContext context) {
    final borderColor = isImportant
        ? InboxColors.checkboxImportant
        : InboxColors.checkbox;
    final fillColor = isChecked ? InboxColors.checkbox : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: InboxSizes.checkbox,
      height: InboxSizes.checkbox,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(
          color: isChecked ? InboxColors.checkbox : borderColor,
          width: InboxSizes.checkboxBorder,
        ),
      ),
      child: isChecked
          ? const Icon(
              Icons.check_rounded,
              size: InboxSizes.checkIcon,
              color: Colors.white,
            )
          : null,
    );
  }
}

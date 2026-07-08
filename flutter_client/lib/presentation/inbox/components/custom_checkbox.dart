import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';

class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({
    required this.isChecked,
    required this.isImportant,
    this.isBusy = false,
    this.onTap,
    super.key,
  });

  final bool isChecked;
  final bool isImportant;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isImportant
        ? InboxColors.checkboxImportant
        : InboxColors.checkbox;
    final checkedColor = InboxColors.success;
    final visual = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: InboxSizes.checkbox,
      height: InboxSizes.checkbox,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isChecked ? checkedColor : Colors.transparent,
        border: Border.all(
          color: isChecked ? checkedColor : borderColor,
          width: InboxSizes.checkboxBorder,
        ),
      ),
      child: isBusy
          ? const Padding(
              padding: EdgeInsets.all(4),
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: InboxColors.accent,
              ),
            )
          : isChecked
          ? const Icon(
              Icons.check_rounded,
              size: InboxSizes.checkIcon,
              color: Colors.white,
            )
          : null,
    );

    if (onTap == null) {
      return SizedBox.square(dimension: 40, child: Center(child: visual));
    }
    return Semantics(
      button: true,
      label: '完成日程',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isBusy ? null : onTap,
        child: SizedBox.square(dimension: 40, child: Center(child: visual)),
      ),
    );
  }
}

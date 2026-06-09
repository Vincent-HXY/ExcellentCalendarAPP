import 'package:flutter/material.dart';

import 'picker_design_tokens.dart';

class PickerBottomActions extends StatelessWidget {
  const PickerBottomActions({
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: PickerSizes.bottomActionHeight,
        child: Row(
          children: [
            Expanded(
              child: _ActionButton(label: '取消', onTap: onCancel),
            ),
            const SizedBox(
              height: 30,
              child: VerticalDivider(
                width: 1,
                thickness: 1,
                color: PickerColors.divider,
              ),
            ),
            Expanded(
              child: _ActionButton(label: '确定', onTap: onConfirm),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(child: Text(label, style: PickerTextStyles.action)),
    );
  }
}

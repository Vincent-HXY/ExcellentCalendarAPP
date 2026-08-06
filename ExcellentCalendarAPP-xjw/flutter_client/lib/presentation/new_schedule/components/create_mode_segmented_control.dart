import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../new_schedule_design_tokens.dart';
import '../new_schedule_page.dart';

class CreateModeSegmentedControl extends StatelessWidget {
  const CreateModeSegmentedControl({
    required this.selectedMode,
    required this.onChanged,
    super.key,
  });

  final CreateScheduleMode selectedMode;
  final ValueChanged<CreateScheduleMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration = disableAnimations
        ? Duration.zero
        : AppMotion.segmentedControl;
    final alignment = selectedMode == CreateScheduleMode.manual
        ? Alignment.centerLeft
        : Alignment.centerRight;

    return Container(
      height: NewScheduleSizes.segmentedHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NewScheduleColors.controlBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: alignment,
            duration: duration,
            curve: AppMotion.enter,
            child: const FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: NewScheduleColors.surface,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _SegmentButton(
                label: '手动填写',
                isSelected: selectedMode == CreateScheduleMode.manual,
                onTap: () => onChanged(CreateScheduleMode.manual),
              ),
              _SegmentButton(
                label: '一键识别',
                isSelected: selectedMode == CreateScheduleMode.aiRecognition,
                onTap: () => onChanged(CreateScheduleMode.aiRecognition),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: disableAnimations
                ? Duration.zero
                : AppMotion.segmentedControl,
            curve: AppMotion.enter,
            style: NewScheduleTextStyles.segment.copyWith(
              color: isSelected
                  ? NewScheduleColors.body
                  : NewScheduleColors.muted,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

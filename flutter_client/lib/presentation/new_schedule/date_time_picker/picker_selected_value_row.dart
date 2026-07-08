import 'package:flutter/material.dart';

import 'picker_design_tokens.dart';
import 'schedule_date_time_picker.dart';

class PickerSelectedValueRow extends StatelessWidget {
  const PickerSelectedValueRow({
    required this.targetLabel,
    required this.selectedDate,
    required this.selectedTime,
    required this.activeStep,
    required this.onDateTap,
    required this.onTimeTap,
    super.key,
  });

  final String targetLabel;
  final DateTime selectedDate;
  final TimeOfDay selectedTime;
  final DateTimePickerStep activeStep;
  final VoidCallback onDateTap;
  final VoidCallback onTimeTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PickerSizes.valueRowHeight,
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(targetLabel, style: PickerTextStyles.label),
          ),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ValuePill(
                label:
                    '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日',
                isActive:
                    activeStep == DateTimePickerStep.calendar ||
                    activeStep == DateTimePickerStep.yearMonthDay,
                onTap: onDateTap,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ValuePill(
                label:
                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                isActive: activeStep == DateTimePickerStep.time,
                onTap: onTimeTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValuePill extends StatelessWidget {
  const _ValuePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: PickerSizes.capsuleTapHeight,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            height: PickerSizes.capsuleVisualHeight,
            padding: const EdgeInsets.symmetric(
              horizontal: PickerSizes.capsuleHorizontalPadding,
            ),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive
                  ? PickerColors.primary
                  : PickerColors.controlBackground,
              borderRadius: BorderRadius.circular(999),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: PickerTextStyles.pill.copyWith(
                  color: isActive ? Colors.white : PickerColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

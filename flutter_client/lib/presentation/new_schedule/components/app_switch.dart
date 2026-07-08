import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: SizedBox(
          width: 58,
          height: 44,
          child: Center(child: _SwitchVisual(value: value)),
        ),
      ),
    );
  }
}

class _SwitchVisual extends StatelessWidget {
  const _SwitchVisual({required this.value});

  final bool value;

  static const _width = 52.0;
  static const _height = 32.0;
  static const _padding = 3.0;
  static const _thumbSize = 26.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: _width,
      height: _height,
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: value ? NewScheduleColors.accent : NewScheduleColors.switchOff,
        borderRadius: BorderRadius.circular(_height / 2),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: _thumbSize,
          height: _thumbSize,
          decoration: const BoxDecoration(
            color: NewScheduleColors.surface,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

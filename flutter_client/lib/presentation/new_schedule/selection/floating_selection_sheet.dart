import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../new_schedule_design_tokens.dart';

Future<T?> showFloatingSelectionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    sheetAnimationStyle: AnimationStyle(
      duration: disableAnimations ? Duration.zero : AppMotion.pickerSheet,
      reverseDuration: disableAnimations ? Duration.zero : AppMotion.routeExit,
      curve: AppMotion.enter,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (context) {
      final viewInsets = MediaQuery.viewInsetsOf(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
        child: builder(context),
      );
    },
  );
}

class FloatingSelectionSheet extends StatelessWidget {
  const FloatingSelectionSheet({
    required this.title,
    required this.content,
    required this.onCancel,
    required this.onConfirm,
    this.subtitle,
    this.maxHeightFactor = 0.78,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget content;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NewScheduleColors.surface,
            borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingSelectionHeader(title: title, subtitle: subtitle),
                Flexible(child: content),
                SelectionSheetActions(onCancel: onCancel, onConfirm: onConfirm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingSelectionHeader extends StatelessWidget {
  const FloatingSelectionHeader({
    required this.title,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: NewScheduleTextStyles.pageTitle.copyWith(fontSize: 20),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: NewScheduleTextStyles.rowValue,
            ),
          ],
        ],
      ),
    );
  }
}

class SelectionSheetActions extends StatelessWidget {
  const SelectionSheetActions({
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
        height: 56,
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
                color: NewScheduleColors.divider,
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
      child: Center(
        child: Text(
          label,
          style: NewScheduleTextStyles.navAction.copyWith(
            color: NewScheduleColors.accent,
          ),
        ),
      ),
    );
  }
}

class SelectionOptionTile extends StatelessWidget {
  const SelectionOptionTile({
    required this.title,
    required this.indicator,
    required this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String title;
  final Widget indicator;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NewScheduleTextStyles.rowLabel.copyWith(
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  indicator,
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Divider(
              height: 1,
              thickness: 1,
              color: NewScheduleColors.divider,
            ),
          ),
      ],
    );
  }
}

class SelectionRadioIndicator extends StatelessWidget {
  const SelectionRadioIndicator({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? NewScheduleColors.accent : NewScheduleColors.muted,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: NewScheduleColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class SelectionCheckboxIndicator extends StatelessWidget {
  const SelectionCheckboxIndicator({required this.selected, super.key});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? NewScheduleColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: selected ? NewScheduleColors.accent : NewScheduleColors.muted,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 17)
          : null,
    );
  }
}

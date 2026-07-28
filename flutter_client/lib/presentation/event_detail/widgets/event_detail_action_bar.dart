import 'dart:ui';

import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';

class EventDetailActionBar extends StatelessWidget {
  const EventDetailActionBar({
    this.onEdit,
    this.onComplete,
    this.isCompleting = false,
    this.isCompleted = false,
    this.isCompleteEnabled = true,
    super.key,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onComplete;
  final bool isCompleting;
  final bool isCompleted;
  final bool isCompleteEnabled;

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(22);
    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: radius, topRight: radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xEEFDFDFD),
            borderRadius: BorderRadius.only(topLeft: radius, topRight: radius),
            boxShadow: [
              BoxShadow(
                color: Color(0x120B3640),
                blurRadius: 14,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: EventDetailSizes.actionBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 38,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _ActionButton(
                        onTap: onEdit,
                        background: const Color(0xFFEAF7F8),
                        icon: Icons.edit_outlined,
                        label: '\u7f16\u8f91',
                        iconColor: EventDetailColors.primaryTeal,
                        labelColor: EventDetailColors.primaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: _ActionButton(
                        onTap: isCompleting || !isCompleteEnabled
                            ? null
                            : onComplete,
                        background: isCompleteEnabled && !isCompleted
                            ? null
                            : EventDetailColors.disabledBlueGray,
                        gradient: isCompleteEnabled && !isCompleted
                            ? const LinearGradient(
                                colors: [Color(0xFF32B3C0), Color(0xFF36BEB8)],
                              )
                            : null,
                        icon: Icons.check_circle_outline_rounded,
                        label: isCompleting
                            ? '\u5904\u7406\u4e2d'
                            : isCompleted
                            ? '\u5df2\u5b8c\u6210'
                            : '\u5b8c\u6210',
                        iconColor: Colors.white,
                        labelColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.labelColor,
    this.background,
    this.gradient,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(20));
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 36,
          decoration: BoxDecoration(
            color: background,
            gradient: gradient,
            borderRadius: radius,
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: iconColor),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

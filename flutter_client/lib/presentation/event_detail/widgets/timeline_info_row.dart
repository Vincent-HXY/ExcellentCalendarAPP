import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';

class TimelineInfoRow extends StatelessWidget {
  const TimelineInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailingValue,
    this.showConnector = true,
    this.onTap,
    super.key,
  });

  final Widget icon;
  final String label;
  final String value;
  final String? trailingValue;
  final bool showConnector;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: EventDetailSizes.scheduleRowHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (showConnector)
                      Positioned(
                        top: EventDetailSizes.scheduleRowHeight / 2,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: EventDetailColors.primaryTealLight,
                        ),
                      ),
                    SizedBox(width: 20, height: 20, child: icon),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              SizedBox(
                width: 42,
                child: Text(label, style: EventDetailTextStyles.timelineLabel),
              ),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EventDetailTextStyles.timelineValue,
                ),
              ),
              if (trailingValue != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailingValue!,
                  style: EventDetailTextStyles.timelineLabel,
                ),
              ],
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Color(0xFF9BA4AA),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

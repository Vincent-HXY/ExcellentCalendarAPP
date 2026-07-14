import 'package:flutter/material.dart';

import '../event_detail_design_tokens.dart';
import '../event_detail_formatters.dart';
import '../models/event_detail_ui_state.dart';
import 'timeline_info_row.dart';

class EventScheduleCard extends StatelessWidget {
  const EventScheduleCard({required this.state, this.onEditField, super.key});

  final EventDetailUiState state;
  final ValueChanged<EventDetailField>? onEditField;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EventDetailSpacing.cardPadding,
        vertical: 2,
      ),
      decoration: eventDetailCardDecoration(),
      child: Column(
        children: [
          TimelineInfoRow(
            icon: const Icon(
              Icons.calendar_today_rounded,
              size: 18,
              color: EventDetailColors.primaryTeal,
            ),
            label: '\u65e5\u671f',
            value: formatEventDate(state.startAt),
            trailingValue: eventWeekdayLabel(state.startAt),
            onTap: () => onEditField?.call(EventDetailField.schedule),
          ),
          TimelineInfoRow(
            icon: const _TimelineRoundIcon(icon: Icons.play_arrow_rounded),
            label: '\u5f00\u59cb',
            value: formatEventTime(state.startAt),
            onTap: () => onEditField?.call(EventDetailField.schedule),
          ),
          TimelineInfoRow(
            icon: const _TimelineRoundIcon(icon: Icons.stop_rounded),
            label: '\u7ed3\u675f',
            value: formatEventTime(state.endAt),
            onTap: () => onEditField?.call(EventDetailField.schedule),
          ),
          TimelineInfoRow(
            icon: const _TimelineRoundIcon(
              icon: Icons.notifications_rounded,
              color: EventDetailColors.disabledBlueGray,
            ),
            label: '\u63d0\u9192',
            value: state.reminderLabel,
            showConnector: false,
            onTap: () => onEditField?.call(EventDetailField.schedule),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Divider(
              height: 4,
              thickness: .5,
              color: EventDetailColors.divider,
            ),
          ),
          SizedBox(
            height: EventDetailSizes.allDayRowHeight,
            child: Row(
              children: [
                const Text(
                  '\u5168\u5929',
                  style: TextStyle(
                    color: EventDetailColors.primaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Transform.scale(
                  scale: .82,
                  child: Switch.adaptive(
                    value: state.isAllDay,
                    activeTrackColor: EventDetailColors.primaryTeal,
                    inactiveTrackColor: EventDetailColors.disabledGray,
                    inactiveThumbColor: Colors.white,
                    onChanged: (_) =>
                        onEditField?.call(EventDetailField.allDay),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRoundIcon extends StatelessWidget {
  const _TimelineRoundIcon({
    required this.icon,
    this.color = EventDetailColors.primaryTeal,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 13),
    );
  }
}

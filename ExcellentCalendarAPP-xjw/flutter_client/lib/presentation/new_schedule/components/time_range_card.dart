import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import 'app_switch.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';

class TimeRangeCard extends StatelessWidget {
  const TimeRangeCard({
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.onAllDayChanged,
    required this.onStartTap,
    required this.onStartTimeTap,
    required this.onStartDateTap,
    required this.onEndTap,
    required this.onEndTimeTap,
    required this.onEndDateTap,
    required this.onTimezoneTap,
    super.key,
  });

  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final ValueChanged<bool> onAllDayChanged;
  final VoidCallback onStartTap;
  final VoidCallback onStartTimeTap;
  final VoidCallback onStartDateTap;
  final VoidCallback onEndTap;
  final VoidCallback onEndTimeTap;
  final VoidCallback onEndDateTap;
  final VoidCallback onTimezoneTap;

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      child: Column(
        children: [
          FormRowItem(
            label: '全天',
            showChevron: false,
            showDivider: true,
            trailing: AppSwitch(
              value: isAllDay,
              semanticLabel: '全天',
              onChanged: onAllDayChanged,
            ),
          ),
          SizedBox(
            height: 108,
            child: Row(
              children: [
                Expanded(
                  child: _TimeBlock(
                    label: '开始',
                    time: _formatTime(startAt),
                    date: _formatDate(startAt),
                    onTap: onStartTap,
                    onTimeTap: onStartTimeTap,
                    onDateTap: onStartDateTap,
                  ),
                ),
                const SizedBox(
                  height: 62,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: NewScheduleColors.divider,
                  ),
                ),
                Expanded(
                  child: _TimeBlock(
                    label: '结束',
                    time: _formatTime(endAt),
                    date: _formatDate(endAt),
                    onTap: onEndTap,
                    onTimeTap: onEndTimeTap,
                    onDateTap: onEndDateTap,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: NewScheduleSpacing.rowHorizontal,
            ),
            child: Divider(
              height: 1,
              thickness: 1,
              color: NewScheduleColors.divider,
            ),
          ),
          FormRowItem(label: '时区', value: 'GMT+08:00 北京', onTap: onTimezoneTap),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    return '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }

  String _formatDate(DateTime value) {
    return '${value.year}/${_twoDigits(value.month)}/${_twoDigits(value.day)}';
  }

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.time,
    required this.date,
    required this.onTap,
    required this.onTimeTap,
    required this.onDateTap,
  });

  final String label;
  final String time;
  final String date;
  final VoidCallback onTap;
  final VoidCallback onTimeTap;
  final VoidCallback onDateTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: NewScheduleTextStyles.timeLabel),
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTimeTap,
              child: Text(time, style: NewScheduleTextStyles.timeValue),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDateTap,
              child: Text(date, style: NewScheduleTextStyles.dateValue),
            ),
          ],
        ),
      ),
    );
  }
}

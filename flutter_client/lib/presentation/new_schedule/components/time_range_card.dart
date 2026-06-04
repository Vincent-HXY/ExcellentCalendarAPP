// 文件作用：新建日程表单的时间范围卡片，展示全天开关、开始/结束时间和时区入口。
// 设计边界：只展示时间字段，时间合法性和重复规则计算应由 Application/Core 处理。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';

class TimeRangeCard extends StatelessWidget {
  const TimeRangeCard({
    required this.isAllDay,
    required this.onAllDayChanged,
    required this.onStartTap,
    required this.onEndTap,
    required this.onTimezoneTap,
    super.key,
  });

  // 数据块作用：全天开关状态。
  final bool isAllDay;
  // 数据块作用：全天开关变化回调。
  final ValueChanged<bool> onAllDayChanged;
  // 数据块作用：点击开始时间块时触发的父级回调。
  final VoidCallback onStartTap;
  // 数据块作用：点击结束时间块时触发的父级回调。
  final VoidCallback onEndTap;
  // 数据块作用：点击时区行时触发的父级回调。
  final VoidCallback onTimezoneTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制时间范围区域，包括全天开关、开始结束时间和时区行。
    // 关键数据：显示的时间/日期/时区仍是静态占位，提交用的 DateTime 在页面状态里。
    return FormSectionCard(
      child: Column(
        children: [
          FormRowItem(
            label: '全天',
            showChevron: false,
            showDivider: true,
            trailing: Switch(
              value: isAllDay,
              activeThumbColor: NewScheduleColors.surface,
              activeTrackColor: NewScheduleColors.accent,
              inactiveThumbColor: NewScheduleColors.surface,
              inactiveTrackColor: NewScheduleColors.switchOff,
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
                    time: '08:00',
                    date: '2026/06/03',
                    onTap: onStartTap,
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
                    time: '09:00',
                    date: '2026/06/03',
                    onTap: onEndTap,
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
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.time,
    required this.date,
    required this.onTap,
  });

  // 数据块作用：时间块上方的小标题，例如开始或结束。
  final String label;
  // 数据块作用：时间文本，例如 08:00。
  final String time;
  // 数据块作用：日期文本，例如 2026/06/03。
  final String date;
  // 数据块作用：点击时间块时触发的父级回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制单个开始/结束时间块。
    // 关键布局：每个时间块固定文本层级，后续接入选择器时保持点击区域不变。
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: NewScheduleTextStyles.timeLabel),
            const SizedBox(height: 10),
            Text(time, style: NewScheduleTextStyles.timeValue),
            const SizedBox(height: 8),
            Text(date, style: NewScheduleTextStyles.dateValue),
          ],
        ),
      ),
    );
  }
}

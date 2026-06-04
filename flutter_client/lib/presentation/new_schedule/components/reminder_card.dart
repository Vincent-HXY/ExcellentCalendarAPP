// 文件作用：新建日程表单的提醒设置卡片，包含提醒时间入口和响铃开关。
// 设计边界：Reminder 是独立实体；这里目前只展示用户意图，不生成 Reminder 记录。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    required this.isRingingReminderEnabled,
    required this.onReminderTap,
    required this.onRingingReminderChanged,
    super.key,
  });

  // 数据块作用：响铃提醒开关状态，目前只影响 Switch 展示。
  final bool isRingingReminderEnabled;
  // 数据块作用：点击提醒时间行时触发的父级回调。
  final VoidCallback onReminderTap;
  // 数据块作用：响铃提醒开关变化回调。
  final ValueChanged<bool> onRingingReminderChanged;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制提醒设置区域，包括提醒时间入口和响铃开关。
    // 关键数据：提醒文案“15 分钟前”是占位展示，后续应由 Reminder 默认规则/用户选择提供。
    return FormSectionCard(
      child: Column(
        children: [
          FormRowItem(
            label: '提醒',
            value: '15 分钟前',
            showDivider: true,
            onTap: onReminderTap,
          ),
          FormRowItem(
            label: '响铃提醒',
            showChevron: false,
            trailing: Switch(
              value: isRingingReminderEnabled,
              activeThumbColor: NewScheduleColors.surface,
              activeTrackColor: NewScheduleColors.accent,
              inactiveThumbColor: NewScheduleColors.surface,
              inactiveTrackColor: NewScheduleColors.switchOff,
              onChanged: onRingingReminderChanged,
            ),
          ),
        ],
      ),
    );
  }
}

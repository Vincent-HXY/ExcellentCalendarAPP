// 文件作用：手动创建日程的表单组合，串联标题、时间、提醒、地点、分类和备注控件。
// 设计边界：这里只组织控件与回调，不计算提醒时间、重复规则或分类推荐。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';
import 'more_settings_header.dart';
import 'reminder_card.dart';
import 'text_input_card.dart';
import 'time_range_card.dart';

class ManualScheduleForm extends StatelessWidget {
  const ManualScheduleForm({
    required this.titleController,
    required this.noteController,
    required this.isAllDay,
    required this.isRingingReminderEnabled,
    required this.isMoreSettingsExpanded,
    required this.onAllDayChanged,
    required this.onRingingReminderChanged,
    required this.onMoreSettingsToggle,
    required this.onTodoTap,
    super.key,
  });

  // 数据块作用：标题输入控制器，由页面持有以参与提交和按钮状态判断。
  final TextEditingController titleController;
  // 数据块作用：备注输入控制器，由页面持有以参与提交。
  final TextEditingController noteController;
  // 数据块作用：全天开关状态。
  final bool isAllDay;
  // 数据块作用：响铃提醒开关状态。
  final bool isRingingReminderEnabled;
  // 数据块作用：更多设置是否展开。
  final bool isMoreSettingsExpanded;
  // 数据块作用：全天开关变化回调。
  final ValueChanged<bool> onAllDayChanged;
  // 数据块作用：响铃提醒开关变化回调。
  final ValueChanged<bool> onRingingReminderChanged;
  // 数据块作用：更多设置标题点击回调。
  final VoidCallback onMoreSettingsToggle;
  // 数据块作用：未实现功能入口的临时提示回调。
  final ValueChanged<String> onTodoTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：组合手动创建日程所需的所有表单卡片。
    // 关键布局：更多设置用 AnimatedSize 折叠，内部控件目前多为功能入口占位。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInputCard(
          titleController: titleController,
          onTypeTap: () => onTodoTap('类型选择功能后续实现'),
        ),
        const SizedBox(height: NewScheduleSpacing.sectionGap),
        TimeRangeCard(
          isAllDay: isAllDay,
          onAllDayChanged: onAllDayChanged,
          onStartTap: () => onTodoTap('开始时间选择功能后续实现'),
          onEndTap: () => onTodoTap('结束时间选择功能后续实现'),
          onTimezoneTap: () => onTodoTap('时区选择功能后续实现'),
        ),
        const SizedBox(height: 8),
        MoreSettingsHeader(
          isExpanded: isMoreSettingsExpanded,
          onTap: onMoreSettingsToggle,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: isMoreSettingsExpanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormSectionCard(
                      child: FormRowItem(
                        label: '重复',
                        value: '仅一次',
                        onTap: () => onTodoTap('重复规则功能后续实现'),
                      ),
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    ReminderCard(
                      isRingingReminderEnabled: isRingingReminderEnabled,
                      onReminderTap: () => onTodoTap('提醒时间选择功能后续实现'),
                      onRingingReminderChanged: onRingingReminderChanged,
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    FormSectionCard(
                      child: FormRowItem(
                        label: '地点',
                        showChevron: false,
                        trailing: const Icon(
                          Icons.location_on_outlined,
                          color: NewScheduleColors.body,
                          size: 28,
                        ),
                        onTap: () => onTodoTap('地点选择功能后续实现'),
                      ),
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    FormSectionCard(
                      child: FormRowItem(
                        label: '日历分类',
                        value: '默认日程',
                        onTap: () => onTodoTap('日历分类功能后续实现'),
                      ),
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    FormSectionCard(
                      child: SizedBox(
                        height: NewScheduleSizes.noteHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                          child: TextField(
                            controller: noteController,
                            maxLines: null,
                            style: NewScheduleTextStyles.rowLabel.copyWith(
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: '备注',
                              hintStyle: NewScheduleTextStyles.rowValue,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

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
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.isRingingReminderEnabled,
    required this.isMoreSettingsExpanded,
    required this.onAllDayChanged,
    required this.onRingingReminderChanged,
    required this.onMoreSettingsToggle,
    required this.onStartTap,
    required this.onStartTimeTap,
    required this.onStartDateTap,
    required this.onEndTap,
    required this.onEndTimeTap,
    required this.onEndDateTap,
    required this.onTodoTap,
    super.key,
  });

  final TextEditingController titleController;
  final TextEditingController noteController;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final bool isRingingReminderEnabled;
  final bool isMoreSettingsExpanded;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<bool> onRingingReminderChanged;
  final VoidCallback onMoreSettingsToggle;
  final VoidCallback onStartTap;
  final VoidCallback onStartTimeTap;
  final VoidCallback onStartDateTap;
  final VoidCallback onEndTap;
  final VoidCallback onEndTimeTap;
  final VoidCallback onEndDateTap;
  final ValueChanged<String> onTodoTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextInputCard(
          titleController: titleController,
          onTypeTap: () => onTodoTap('类型选择功能后续实现'),
        ),
        const SizedBox(height: NewScheduleSpacing.sectionGap),
        TimeRangeCard(
          startAt: startAt,
          endAt: endAt,
          isAllDay: isAllDay,
          onAllDayChanged: onAllDayChanged,
          onStartTap: onStartTap,
          onStartTimeTap: onStartTimeTap,
          onStartDateTap: onStartDateTap,
          onEndTap: onEndTap,
          onEndTimeTap: onEndTimeTap,
          onEndDateTap: onEndDateTap,
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

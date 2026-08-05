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
    required this.locationController,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.isRingingReminderEnabled,
    required this.isMoreSettingsExpanded,
    required this.recurrenceLabel,
    required this.reminderSummary,
    required this.timezoneLabel,
    required this.onAllDayChanged,
    required this.onRingingReminderChanged,
    required this.onMoreSettingsToggle,
    required this.onStartTap,
    required this.onStartTimeTap,
    required this.onStartDateTap,
    required this.onEndTap,
    required this.onEndTimeTap,
    required this.onEndDateTap,
    required this.onRecurrenceTap,
    required this.onReminderTap,
    required this.onLocationMapTap,
    required this.onTodoTap,
    super.key,
  });

  final TextEditingController titleController;
  final TextEditingController noteController;
  final TextEditingController locationController;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final bool isRingingReminderEnabled;
  final bool isMoreSettingsExpanded;
  final String recurrenceLabel;
  final String reminderSummary;
  final String timezoneLabel;
  final ValueChanged<bool> onAllDayChanged;
  final ValueChanged<bool> onRingingReminderChanged;
  final VoidCallback onMoreSettingsToggle;
  final VoidCallback onStartTap;
  final VoidCallback onStartTimeTap;
  final VoidCallback onStartDateTap;
  final VoidCallback onEndTap;
  final VoidCallback onEndTimeTap;
  final VoidCallback onEndDateTap;
  final VoidCallback onRecurrenceTap;
  final VoidCallback onReminderTap;
  final VoidCallback onLocationMapTap;
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
          timezoneLabel: timezoneLabel,
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
                        value: recurrenceLabel,
                        onTap: onRecurrenceTap,
                      ),
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    ReminderCard(
                      reminderSummary: reminderSummary,
                      isRingingReminderEnabled: isRingingReminderEnabled,
                      onReminderTap: onReminderTap,
                      onRingingReminderChanged: onRingingReminderChanged,
                    ),
                    const SizedBox(height: NewScheduleSpacing.sectionGap),
                    FormSectionCard(
                      child: _LocationInputRow(
                        controller: locationController,
                        onMapTap: onLocationMapTap,
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

class _LocationInputRow extends StatelessWidget {
  const _LocationInputRow({required this.controller, required this.onMapTap});

  final TextEditingController controller;
  final VoidCallback onMapTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NewScheduleSizes.rowHeight,
      child: Padding(
        padding: const EdgeInsets.only(
          left: NewScheduleSpacing.rowHorizontal,
          right: 14,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                style: NewScheduleTextStyles.rowLabel.copyWith(
                  fontWeight: FontWeight.w400,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '地点',
                  hintStyle: NewScheduleTextStyles.rowValue,
                  isCollapsed: true,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMapTap,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.location_on_outlined,
                  color: NewScheduleColors.body,
                  size: 27,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

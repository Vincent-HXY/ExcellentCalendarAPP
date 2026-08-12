import 'package:flutter/material.dart';

import '../../../application/anniversary/anniversary_form_controller.dart';
import '../../../application/anniversary/anniversary_models.dart';
import '../anniversary_design_tokens.dart';
import 'anniversary_form_section.dart';

class AnniversaryFormFields extends StatelessWidget {
  const AnniversaryFormFields({
    required this.controller,
    required this.titleController,
    required this.noteController,
    required this.onPickDate,
    super.key,
  });

  final AnniversaryFormController controller;
  final TextEditingController titleController;
  final TextEditingController noteController;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BasicsSection(
          controller: controller,
          titleController: titleController,
          onPickDate: onPickDate,
        ),
        const SizedBox(height: AnniversarySpacing.sectionGap),
        _ScheduleSection(controller: controller),
        const SizedBox(height: AnniversarySpacing.sectionGap),
        _DetailsSection(controller: controller, noteController: noteController),
      ],
    );
  }
}

class _BasicsSection extends StatelessWidget {
  const _BasicsSection({
    required this.controller,
    required this.titleController,
    required this.onPickDate,
  });

  final AnniversaryFormController controller;
  final TextEditingController titleController;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return AnniversaryFormSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('anniversary-title-field'),
            controller: titleController,
            onChanged: controller.setTitle,
            maxLength: 40,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：我们的纪念日',
              prefixIcon: Icon(
                Icons.edit_rounded,
                color: AnniversaryColors.primaryTeal,
              ),
              border: InputBorder.none,
              counterText: '',
            ),
            validator: (_) => controller.titleError,
          ),
          const _SectionDivider(),
          _DateField(
            date: controller.date,
            errorText: controller.dateError,
            onTap: onPickDate,
          ),
          const _SectionDivider(),
          const _SectionTitle(title: '日历类型'),
          const SizedBox(height: 12),
          _CalendarChoices(controller: controller),
        ],
      ),
    );
  }
}

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({required this.controller});

  final AnniversaryFormController controller;

  @override
  Widget build(BuildContext context) {
    return AnniversaryFormSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              Icons.repeat_rounded,
              color: AnniversaryColors.primaryTeal,
            ),
            title: const Text(
              '每年重复',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            value: controller.repeatYearly,
            activeTrackColor: AnniversaryColors.primaryTeal,
            onChanged: controller.setRepeatYearly,
          ),
        ],
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({
    required this.controller,
    required this.noteController,
  });

  final AnniversaryFormController controller;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    return AnniversaryFormSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle(title: '重要性'),
          const SizedBox(height: 12),
          _ImportanceChoices(controller: controller),
          const _SectionDivider(),
          TextField(
            key: const ValueKey('anniversary-note-field'),
            controller: noteController,
            onChanged: controller.setNote,
            maxLines: 4,
            minLines: 3,
            maxLength: 300,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              alignLabelWithHint: true,
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 54),
                child: Icon(
                  Icons.notes_rounded,
                  color: AnniversaryColors.primaryTeal,
                ),
              ),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarChoices extends StatelessWidget {
  const _CalendarChoices({required this.controller});

  final AnniversaryFormController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ChoicePill(
          key: const ValueKey('anniversary-calendar-solar'),
          label: '公历',
          selected: controller.calendarType == AnniversaryCalendarType.solar,
          onSelected: () {},
        ),
        _ChoicePill(
          key: const ValueKey('anniversary-calendar-lunar'),
          label: '农历（暂不支持）',
          selected: controller.calendarType == AnniversaryCalendarType.lunar,
          onSelected: () {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('当前版本暂不支持农历')));
          },
        ),
      ],
    );
  }
}

class _ImportanceChoices extends StatelessWidget {
  const _ImportanceChoices({required this.controller});

  final AnniversaryFormController controller;

  @override
  Widget build(BuildContext context) {
    const labels = {
      AnniversaryImportance.unimportantNotUrgent: '普通',
      AnniversaryImportance.importantNotUrgent: '重要不紧急',
      AnniversaryImportance.unimportantUrgent: '不重要紧急',
      AnniversaryImportance.importantUrgent: '重要且紧急',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final importance in AnniversaryImportance.values)
          _ChoicePill(
            key: ValueKey('anniversary-importance-${importance.name}'),
            label: labels[importance]!,
            selected: controller.importance == importance,
            onSelected: () => controller.setImportance(importance),
          ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.errorText,
    required this.onTap,
  });

  final DateTime? date;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: date == null ? '选择纪念日日期' : '纪念日日期 ${_formatDate(date!)}',
          child: InkWell(
            key: const ValueKey('anniversary-date-field'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AnniversarySizes.minTapTarget,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    color: AnniversaryColors.primaryTeal,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      '日期',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    date == null ? '选择日期' : _formatDate(date!),
                    style: TextStyle(
                      color: date == null
                          ? AnniversaryColors.secondaryText
                          : AnniversaryColors.primaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AnniversaryColors.secondaryText,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: AnniversaryColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}.$month.$day';
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        showCheckmark: false,
        selectedColor: AnniversaryColors.selectedChip,
        backgroundColor: const Color(0xFFF4F7F7),
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: selected
              ? AnniversaryColors.primaryTeal
              : AnniversaryColors.secondaryText,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AnniversaryColors.primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: AnniversaryColors.divider),
    );
  }
}

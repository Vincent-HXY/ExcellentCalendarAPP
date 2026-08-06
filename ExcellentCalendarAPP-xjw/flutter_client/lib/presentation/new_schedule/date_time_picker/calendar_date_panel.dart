import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import 'picker_design_tokens.dart';
import 'schedule_date_time_picker.dart';

class CalendarDatePanel extends StatelessWidget {
  const CalendarDatePanel({
    required this.selectedDate,
    required this.visibleMonth,
    required this.today,
    required this.calendarSystem,
    required this.monthDirection,
    required this.target,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onMonthTitleTap,
    required this.onDateSelected,
    required this.onCalendarSystemToggle,
    super.key,
  });

  final DateTime selectedDate;
  final DateTime visibleMonth;
  final DateTime today;
  final CalendarSystem calendarSystem;
  final int monthDirection;
  final PickerTarget target;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onMonthTitleTap;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onCalendarSystemToggle;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return Column(
      children: [
        LunarToggleRow(
          isLunar: calendarSystem == CalendarSystem.lunar,
          onTap: onCalendarSystemToggle,
        ),
        if (calendarSystem == CalendarSystem.lunar) ...[
          const SizedBox(height: 10),
          const _LunarPlaceholder(),
        ],
        const SizedBox(height: 18),
        CalendarMonthHeader(
          visibleMonth: visibleMonth,
          onPreviousMonth: onPreviousMonth,
          onNextMonth: onNextMonth,
          onMonthTitleTap: onMonthTitleTap,
        ),
        const SizedBox(height: 22),
        const CalendarWeekHeader(),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: disableAnimations ? Duration.zero : AppMotion.pickerMonth,
          switchInCurve: AppMotion.enter,
          switchOutCurve: AppMotion.enter,
          transitionBuilder: (child, animation) {
            final direction = monthDirection == 0 ? 1 : monthDirection;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(direction > 0 ? 0.08 : -0.08, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: CalendarDayGrid(
            key: ValueKey('${visibleMonth.year}-${visibleMonth.month}'),
            visibleMonth: visibleMonth,
            selectedDate: selectedDate,
            today: today,
            onDateSelected: onDateSelected,
          ),
        ),
      ],
    );
  }
}

class LunarToggleRow extends StatelessWidget {
  const LunarToggleRow({required this.isLunar, required this.onTap, super.key});

  final bool isLunar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PickerColors.divider),
            bottom: BorderSide(color: PickerColors.divider),
          ),
        ),
        child: Row(
          children: [
            const Text('农历', style: PickerTextStyles.label),
            const Spacer(),
            Switch(
              value: isLunar,
              activeThumbColor: PickerColors.surface,
              activeTrackColor: PickerColors.primary,
              inactiveThumbColor: PickerColors.surface,
              inactiveTrackColor: PickerColors.switchOff,
              onChanged: (_) => onTap(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LunarPlaceholder extends StatelessWidget {
  const _LunarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PickerColors.controlBackground,
        borderRadius: BorderRadius.circular(AppRadius.formCard),
      ),
      child: const Text('农历转换能力后续接入，当前仍按公历日期选择。', style: PickerTextStyles.week),
    );
  }
}

class CalendarMonthHeader extends StatelessWidget {
  const CalendarMonthHeader({
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onMonthTitleTap,
    super.key,
  });

  final DateTime visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onMonthTitleTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HeaderIconButton(
          icon: Icons.chevron_left_rounded,
          onTap: onPreviousMonth,
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onMonthTitleTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${visibleMonth.year}年${visibleMonth.month}月',
                  style: PickerTextStyles.calendarMonth,
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  color: PickerColors.textSecondary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        _HeaderIconButton(
          icon: Icons.chevron_right_rounded,
          onTap: onNextMonth,
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Icon(icon, color: PickerColors.textPrimary, size: 34),
      ),
    );
  }
}

class CalendarWeekHeader extends StatelessWidget {
  const CalendarWeekHeader({super.key});

  static const _weekdays = ['日', '一', '二', '三', '四', '五', '六'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final weekday in _weekdays)
          Expanded(
            child: Center(child: Text(weekday, style: PickerTextStyles.week)),
          ),
      ],
    );
  }
}

class CalendarDayGrid extends StatelessWidget {
  const CalendarDayGrid({
    required this.visibleMonth,
    required this.selectedDate,
    required this.today,
    required this.onDateSelected,
    super.key,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime today;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final days = _buildVisibleDays(visibleMonth);

    return SizedBox(
      height: PickerSizes.dayCellExtent * 6,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: days.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisExtent: PickerSizes.dayCellExtent,
        ),
        itemBuilder: (context, index) {
          final day = days[index];
          return CalendarDayCell(
            date: day,
            isCurrentMonth: day.month == visibleMonth.month,
            isSelected: _isSameDate(day, selectedDate),
            isToday: _isSameDate(day, today),
            onTap: () => onDateSelected(day),
          );
        },
      ),
    );
  }

  static List<DateTime> _buildVisibleDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month);
    final start = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    return List.generate(42, (index) => start.add(Duration(days: index)));
  }

  static bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    required this.date,
    required this.isCurrentMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
    super.key,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final textColor = isSelected
        ? Colors.white
        : isCurrentMonth
        ? PickerColors.textPrimary
        : PickerColors.textDisabled;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedScale(
          scale: isSelected ? 1 : 0.92,
          duration: disableAnimations
              ? Duration.zero
              : AppMotion.pickerDaySelection,
          curve: AppMotion.enter,
          child: AnimatedContainer(
            duration: disableAnimations
                ? Duration.zero
                : AppMotion.pickerDaySelection,
            curve: AppMotion.enter,
            width: PickerSizes.dayCircle,
            height: PickerSizes.dayCircle,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? PickerColors.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: PickerColors.primary, width: 1)
                  : null,
            ),
            child: Text(
              '${date.day}',
              style: PickerTextStyles.day.copyWith(color: textColor),
            ),
          ),
        ),
      ),
    );
  }
}

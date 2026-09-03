import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';
import '../../../application/calendar/calendar_models.dart';
import '../../../native_contract/calendar/calendar_response_dtos.dart';
import '../calendar_design_tokens.dart';

class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    required this.state,
    required this.onSelectDate,
    this.transitionDirection = 1,
    super.key,
  });

  final CalendarState state;
  final ValueChanged<DateTime> onSelectDate;
  final int transitionDirection;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final dates = CalendarDateMath.dates(state.visibleRange);
    final summaries = {for (final day in state.rangeDays) day.date: day};
    final motion = CalendarMotion.effective(context, CalendarMotion.page);
    final dateGrid = _DateGrid(
      key: ValueKey(
        '${state.viewMode.name}:'
        '${CalendarDateMath.formatDate(state.visibleRangeStart)}:'
        '${state.snapshotToken ?? 'loading'}',
      ),
      dates: dates,
      summaries: summaries,
      selectedDate: state.selectedDate,
      today: state.today,
      anchorMonth: state.anchorDate.month,
      anchorYear: state.anchorDate.year,
      viewMode: state.viewMode,
      onSelectDate: onSelectDate,
    );
    final dateGridSurface = CalendarMotion.isReduced(context)
        ? dateGrid
        : AnimatedSize(
            duration: CalendarMotion.collapse,
            curve: CalendarMotion.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: motion,
              switchInCurve: CalendarMotion.enter,
              switchOutCurve: CalendarMotion.enter,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: Offset(0.08 * transitionDirection, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: dateGrid,
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(CalendarRadius.panel),
        border: Border.all(color: palette.outline),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
        child: Column(
          children: [
            const _WeekdayHeader(),
            const SizedBox(height: 4),
            dateGridSurface,
            if (state.rangePhase == CalendarRangePhase.loading ||
                state.rangePhase == CalendarRangePhase.refreshing)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(
                    key: ValueKey('calendar-range-progress'),
                    minHeight: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  static const labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final label in labels)
        Expanded(
          child: Semantics(
            header: true,
            label: '星期$label',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _DateGrid extends StatelessWidget {
  const _DateGrid({
    required this.dates,
    required this.summaries,
    required this.selectedDate,
    required this.today,
    required this.anchorMonth,
    required this.anchorYear,
    required this.viewMode,
    required this.onSelectDate,
    super.key,
  });

  final List<DateTime> dates;
  final Map<String, CalendarRangeDaySummaryDto> summaries;
  final DateTime selectedDate;
  final DateTime today;
  final int anchorMonth;
  final int anchorYear;
  final CalendarViewMode viewMode;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final cellHeight = (52 * textScale.clamp(1.0, 1.55)).clamp(52.0, 80.0);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dates.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: cellWidth / cellHeight,
          ),
          itemBuilder: (context, index) {
            final date = dates[index];
            return _DateCell(
              date: date,
              summary: summaries[CalendarDateMath.formatDate(date)],
              isSelected: CalendarDateMath.isSameDate(date, selectedDate),
              isToday: CalendarDateMath.isSameDate(date, today),
              isAdjacentMonth:
                  viewMode == CalendarViewMode.month &&
                  (date.year != anchorYear || date.month != anchorMonth),
              onTap: () => onSelectDate(date),
            );
          },
        );
      },
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.date,
    required this.summary,
    required this.isSelected,
    required this.isToday,
    required this.isAdjacentMonth,
    required this.onTap,
  });

  final DateTime date;
  final CalendarRangeDaySummaryDto? summary;
  final bool isSelected;
  final bool isToday;
  final bool isAdjacentMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final semanticLabel = _semanticLabel();
    return Semantics(
      key: ValueKey('calendar-date-${CalendarDateMath.formatDate(date)}'),
      button: true,
      selected: isSelected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Opacity(
            opacity: isAdjacentMonth ? 0.58 : 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: CalendarMotion.effective(
                    context,
                    CalendarMotion.selection,
                  ),
                  curve: CalendarMotion.enter,
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? scheme.primary : Colors.transparent,
                    border: isToday && !isSelected
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${date.day}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? scheme.onPrimary
                              : scheme.onSurface,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (summary?.hasOpenEvent == true)
                        _Dot(color: palette.event),
                      if (summary?.hasPendingHabit == true)
                        _Dot(color: palette.habit),
                      if (summary?.hasAnniversary == true)
                        _Dot(color: palette.anniversary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel() {
    final parts = <String>[
      '${date.year}年${date.month}月${date.day}日',
      '星期${const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}',
      if (isToday) '今天',
      if (isSelected) '已选中',
      if (summary?.hasOpenEvent == true) '有日程',
      if (summary?.hasPendingHabit == true) '有待完成习惯',
      if (summary?.hasAnniversary == true) '有纪念日',
    ];
    return parts.join('，');
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1.5),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

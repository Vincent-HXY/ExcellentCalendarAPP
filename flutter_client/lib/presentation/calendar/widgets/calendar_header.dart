import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    required this.anchorDate,
    required this.viewMode,
    required this.onPrevious,
    required this.onNext,
    required this.onChooseMonth,
    required this.showToday,
    required this.onToday,
    required this.onToggleMode,
    required this.onTimeline,
    required this.onSettings,
    super.key,
  });

  final DateTime anchorDate;
  final CalendarViewMode viewMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onChooseMonth;
  final bool showToday;
  final VoidCallback onToday;
  final VoidCallback onToggleMode;
  final VoidCallback onTimeline;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final title = '${anchorDate.year}年${anchorDate.month}月';
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 390 || textScale > 1.35;
        final titleRow = Row(
          mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _HeaderIconButton(
              tooltip: viewMode == CalendarViewMode.week ? '上一周' : '上个月',
              icon: Icons.chevron_left_rounded,
              onPressed: onPrevious,
            ),
            Flexible(
              child: TextButton.icon(
                key: const ValueKey('calendar-year-month-button'),
                onPressed: onChooseMonth,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                label: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),
            _HeaderIconButton(
              tooltip: viewMode == CalendarViewMode.week ? '下一周' : '下个月',
              icon: Icons.chevron_right_rounded,
              onPressed: onNext,
            ),
          ],
        );
        final tools = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            if (showToday)
              Semantics(
                button: true,
                label: '回到今天',
                child: FilledButton.tonalIcon(
                  key: const ValueKey('calendar-today-button'),
                  onPressed: onToday,
                  icon: const Icon(Icons.today_rounded, size: 18),
                  label: const Text('今天'),
                ),
              ),
            _HeaderIconButton(
              key: const ValueKey('calendar-mode-button'),
              tooltip: viewMode == CalendarViewMode.week ? '展开月视图' : '收起为周视图',
              icon: viewMode == CalendarViewMode.week
                  ? Icons.calendar_view_month_rounded
                  : Icons.view_week_rounded,
              onPressed: onToggleMode,
            ),
            _HeaderIconButton(
              key: const ValueKey('calendar-timeline-button'),
              tooltip: '时间线视图',
              icon: Icons.view_timeline_rounded,
              onPressed: onTimeline,
            ),
            _HeaderIconButton(
              key: const ValueKey('calendar-settings-button'),
              tooltip: '日历设置',
              icon: Icons.more_horiz_rounded,
              onPressed: onSettings,
            ),
          ],
        );
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleRow, const SizedBox(height: 6), tools],
          );
        }
        return Row(
          children: [
            Expanded(child: titleRow),
            const SizedBox(width: 12),
            tools,
          ],
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: SizedBox.square(
      dimension: 48,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    ),
  );
}

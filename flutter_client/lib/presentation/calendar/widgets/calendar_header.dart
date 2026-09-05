import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    required this.anchorDate,
    required this.viewMode,
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
  final VoidCallback onChooseMonth;
  final bool showToday;
  final VoidCallback onToday;
  final VoidCallback onToggleMode;
  final VoidCallback onTimeline;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final title = _chineseMonth(anchorDate.month);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final headlineStyle = Theme.of(context).textTheme.headlineSmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 320 || textScale > 1.35;
        final titleRow = Row(
          mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Flexible(
              child: TextButton(
                key: const ValueKey('calendar-year-month-button'),
                onPressed: onChooseMonth,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: headlineStyle?.copyWith(
                    fontSize: (headlineStyle.fontSize ?? 24) * 2 / 3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            if (showToday) ...[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: '回到今天',
                child: TextButton(
                  key: const ValueKey('calendar-today-button'),
                  onPressed: onToday,
                  child: const Text('今天'),
                ),
              ),
            ],
          ],
        );
        final tools = Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: stacked ? WrapAlignment.start : WrapAlignment.end,
          children: [
            _HeaderIconButton(
              key: const ValueKey('calendar-mode-button'),
              tooltip: viewMode == CalendarViewMode.week ? '展开月视图' : '收起为周视图',
              icon: Icons.tune_rounded,
              onPressed: onToggleMode,
            ),
            _HeaderIconButton(
              key: const ValueKey('calendar-timeline-button'),
              tooltip: '时间线视图',
              icon: Icons.view_agenda_outlined,
              onPressed: onTimeline,
            ),
            _HeaderIconButton(
              key: const ValueKey('calendar-settings-button'),
              tooltip: '日历设置',
              icon: Icons.more_vert_rounded,
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
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          backgroundColor: Colors.transparent,
          hoverColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.06),
          highlightColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.08),
        ),
        icon: Icon(icon, size: 28),
      ),
    ),
  );
}

String _chineseMonth(int month) => const [
  '一月',
  '二月',
  '三月',
  '四月',
  '五月',
  '六月',
  '七月',
  '八月',
  '九月',
  '十月',
  '十一月',
  '十二月',
][month - 1];

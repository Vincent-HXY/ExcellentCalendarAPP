import 'package:flutter/material.dart';

import '../../../application/calendar/calendar_date_math.dart';
import '../../../application/calendar/calendar_models.dart';
import '../../../native_contract/calendar/calendar_response_dtos.dart';
import '../calendar_design_tokens.dart';

typedef CalendarNavigatePeriod = Future<void> Function(int delta);

const _calendarCellHeight = 52.0;

class CalendarGrid extends StatefulWidget {
  const CalendarGrid({
    required this.state,
    required this.expansion,
    required this.onSelectDate,
    required this.onNavigatePeriod,
    super.key,
  });

  final CalendarState state;
  final Animation<double> expansion;
  final ValueChanged<DateTime> onSelectDate;
  final CalendarNavigatePeriod onNavigatePeriod;

  @override
  State<CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid>
    with SingleTickerProviderStateMixin {
  static const _velocityThreshold = 700.0;
  static const _rowCount = 6;

  late final AnimationController _settleController;
  final ValueNotifier<double> _dragOffset = ValueNotifier(0);
  double _pageWidth = 0;
  double _animationStart = 0;
  double _animationTarget = 0;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(vsync: this)
      ..addListener(_handleSettleTick);
  }

  @override
  void didUpdateWidget(covariant CalendarGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.viewMode != widget.state.viewMode && !_isSettling) {
      _dragOffset.value = 0;
    }
  }

  @override
  void dispose() {
    _settleController
      ..removeListener(_handleSettleTick)
      ..dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _handleSettleTick() {
    final progress = Curves.easeOutCubic.transform(_settleController.value);
    _dragOffset.value =
        _animationStart + (_animationTarget - _animationStart) * progress;
  }

  void _handleDragStart(DragStartDetails details) {
    if (_isSettling) return;
    _settleController.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isSettling || _pageWidth <= 0) return;
    _dragOffset.value = (_dragOffset.value + details.delta.dx).clamp(
      -_pageWidth,
      _pageWidth,
    );
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isSettling || _pageWidth <= 0) return;
    final velocity = details.primaryVelocity ?? 0;
    final crossedMiddle = _dragOffset.value.abs() >= _pageWidth * 0.5;
    final int? delta;
    if (velocity.abs() >= _velocityThreshold) {
      delta = velocity < 0 ? 1 : -1;
    } else if (crossedMiddle) {
      delta = _dragOffset.value < 0 ? 1 : -1;
    } else {
      delta = null;
    }
    _settle(delta);
  }

  void _handleDragCancel() {
    if (!_isSettling) _settle(null);
  }

  Future<void> _settle(int? delta) async {
    if (_pageWidth <= 0) return;
    _isSettling = true;
    _animationStart = _dragOffset.value;
    _animationTarget = switch (delta) {
      1 => -_pageWidth,
      -1 => _pageWidth,
      _ => 0,
    };
    final remainingRatio =
        ((_animationTarget - _animationStart).abs() / _pageWidth).clamp(
          0.42,
          1.0,
        );
    final duration = CalendarMotion.effective(
      context,
      Duration(
        milliseconds: (CalendarMotion.page.inMilliseconds * remainingRatio)
            .round(),
      ),
    );
    if (duration == Duration.zero) {
      _dragOffset.value = _animationTarget;
    } else {
      _settleController.duration = duration;
      await _settleController.forward(from: 0);
    }
    if (!mounted) return;
    _dragOffset.value = 0;
    if (delta != null) await widget.onNavigatePeriod(delta);
    _isSettling = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final summaries = {for (final day in state.rangeDays) day.date: day};
    return Padding(
      key: const ValueKey('calendar-grid-canvas'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        children: [
          const _WeekdayHeader(),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              _pageWidth = constraints.maxWidth;
              final previousAnchor = _periodAnchor(state, -1);
              final nextAnchor = _periodAnchor(state, 1);
              final previousRange = _sixWeekRange(previousAnchor);
              final currentRange = _sixWeekRange(state.anchorDate);
              final nextRange = _sixWeekRange(nextAnchor);
              const cellHeight = _calendarCellHeight;
              final fullGridHeight = cellHeight * _rowCount;
              final track = RepaintBoundary(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _periodPage(
                      key: const ValueKey('calendar-period-previous'),
                      width: _pageWidth,
                      range: previousRange,
                      anchor: previousAnchor,
                      cellHeight: cellHeight,
                      preview: true,
                      prefix: 'calendar-preview-previous-date',
                    ),
                    _periodPage(
                      key: const ValueKey('calendar-period-current'),
                      width: _pageWidth,
                      range: currentRange,
                      anchor: state.selectedDate,
                      cellHeight: cellHeight,
                      summaries: summaries,
                      prefix: 'calendar-date',
                    ),
                    _periodPage(
                      key: const ValueKey('calendar-period-next'),
                      width: _pageWidth,
                      range: nextRange,
                      anchor: nextAnchor,
                      cellHeight: cellHeight,
                      preview: true,
                      prefix: 'calendar-preview-next-date',
                    ),
                  ],
                ),
              );
              return GestureDetector(
                key: const ValueKey('calendar-period-drag-surface'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                onHorizontalDragCancel: _handleDragCancel,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_dragOffset, widget.expansion]),
                  child: track,
                  builder: (context, child) {
                    final pagerHeight =
                        cellHeight *
                        (1 + (_rowCount - 1) * widget.expansion.value);
                    return ClipRect(
                      child: SizedBox(
                        width: _pageWidth,
                        height: pagerHeight,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: _pageWidth * 3,
                          maxWidth: _pageWidth * 3,
                          minHeight: fullGridHeight,
                          maxHeight: fullGridHeight,
                          child: Transform.translate(
                            key: const ValueKey('calendar-period-track'),
                            offset: Offset(-_pageWidth + _dragOffset.value, 0),
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          SizedBox(
            height: 8,
            child:
                state.rangePhase == CalendarRangePhase.loading ||
                    state.rangePhase == CalendarRangePhase.refreshing
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: const LinearProgressIndicator(
                        key: ValueKey('calendar-range-progress'),
                        minHeight: 2,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _periodPage({
    required Key key,
    required double width,
    required CalendarDateRange range,
    required DateTime anchor,
    required double cellHeight,
    required String prefix,
    Map<String, CalendarRangeDaySummaryDto> summaries = const {},
    bool preview = false,
  }) {
    final grid = RepaintBoundary(
      child: _DateGrid(
        dates: CalendarDateMath.dates(range),
        summaries: summaries,
        selectedDate: widget.state.selectedDate,
        today: widget.state.today,
        anchorMonth: anchor.month,
        anchorYear: anchor.year,
        onSelectDate: widget.onSelectDate,
        isPreview: preview,
        cellKeyPrefix: prefix,
      ),
    );
    final selectedRow = (anchor.difference(range.start).inDays ~/ 7)
        .clamp(0, _rowCount - 1)
        .toDouble();
    final page = AnimatedBuilder(
      animation: widget.expansion,
      child: grid,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          -selectedRow * cellHeight * (1 - widget.expansion.value),
        ),
        child: child,
      ),
    );
    return SizedBox(
      key: key,
      width: width,
      child: preview
          ? ExcludeSemantics(
              child: Opacity(
                key: ValueKey('$prefix-opacity'),
                opacity: 0.46,
                child: page,
              ),
            )
          : page,
    );
  }

  DateTime _periodAnchor(CalendarState state, int delta) =>
      state.viewMode == CalendarViewMode.week
      ? state.selectedDate.add(Duration(days: 7 * delta))
      : CalendarDateMath.addMonthsClamped(state.selectedDate, delta);

  CalendarDateRange _sixWeekRange(DateTime anchor) {
    final month = CalendarDateMath.visibleRange(anchor, CalendarViewMode.month);
    return CalendarDateRange(
      start: month.start,
      end: month.start.add(const Duration(days: 42)),
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
    required this.onSelectDate,
    required this.isPreview,
    required this.cellKeyPrefix,
  });

  final List<DateTime> dates;
  final Map<String, CalendarRangeDaySummaryDto> summaries;
  final DateTime selectedDate;
  final DateTime today;
  final int anchorMonth;
  final int anchorYear;
  final ValueChanged<DateTime> onSelectDate;
  final bool isPreview;
  final String cellKeyPrefix;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: dates.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: cellWidth / _calendarCellHeight,
          ),
          itemBuilder: (context, index) {
            final date = dates[index];
            return _DateCell(
              cellKey: ValueKey(
                '$cellKeyPrefix-${CalendarDateMath.formatDate(date)}',
              ),
              date: date,
              summary: summaries[CalendarDateMath.formatDate(date)],
              isSelected:
                  !isPreview && CalendarDateMath.isSameDate(date, selectedDate),
              isToday: !isPreview && CalendarDateMath.isSameDate(date, today),
              isAdjacentMonth:
                  (date.year != anchorYear || date.month != anchorMonth),
              isPreview: isPreview,
              onTap: isPreview ? null : () => onSelectDate(date),
            );
          },
        );
      },
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({
    required this.cellKey,
    required this.date,
    required this.summary,
    required this.isSelected,
    required this.isToday,
    required this.isAdjacentMonth,
    required this.isPreview,
    required this.onTap,
  });

  final Key cellKey;
  final DateTime date;
  final CalendarRangeDaySummaryDto? summary;
  final bool isSelected;
  final bool isToday;
  final bool isAdjacentMonth;
  final bool isPreview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final semanticLabel = _semanticLabel();
    return Semantics(
      key: cellKey,
      button: onTap != null,
      selected: isSelected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Opacity(
            opacity: !isPreview && isAdjacentMonth ? 0.58 : 1,
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
                              : isPreview
                              ? scheme.onSurfaceVariant
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

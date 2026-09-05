import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/calendar/calendar_controller.dart';
import '../../application/calendar/calendar_date_math.dart';
import '../../gateway_interfaces/calendar_gateway.dart';
import '../../native_contract/calendar/calendar_response_dtos.dart';
import '../inbox/components/add_task_button.dart';
import 'calendar_design_tokens.dart';
import 'widgets/calendar_grid.dart';
import 'widgets/calendar_header.dart';
import 'widgets/calendar_sections.dart';

enum CalendarCreateTarget { event, habit, anniversary }

typedef CalendarOpenEvent =
    Future<bool?> Function(BuildContext context, CalendarEventItemDto item);
typedef CalendarOpenHabit =
    Future<bool?> Function(BuildContext context, CalendarHabitItemDto item);
typedef CalendarOpenAnniversary =
    Future<bool?> Function(
      BuildContext context,
      CalendarAnniversaryItemDto item,
    );
typedef CalendarCreateItem =
    Future<bool?> Function(
      BuildContext context,
      CalendarCreateTarget target,
      DateTime initialDate,
    );

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    this.controller,
    this.gateway,
    this.timezoneProvider,
    this.nowProvider,
    this.disposeInjectedController = false,
    this.onOpenEvent,
    this.onOpenHabit,
    this.onOpenAnniversary,
    this.onCreateItem,
    super.key,
  }) : assert(
         controller != null || gateway != null && timezoneProvider != null,
         'Provide a controller or a gateway plus timezoneProvider.',
       );

  final CalendarController? controller;
  final CalendarGateway? gateway;
  final CalendarTimezoneProvider? timezoneProvider;
  final CalendarNowProvider? nowProvider;
  final bool disposeInjectedController;
  final CalendarOpenEvent? onOpenEvent;
  final CalendarOpenHabit? onOpenHabit;
  final CalendarOpenAnniversary? onOpenAnniversary;
  final CalendarCreateItem? onCreateItem;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage>
    with
        RestorationMixin,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  static const _calendarDragExtent = 260.0;
  static const _verticalVelocityThreshold = 650.0;

  final RestorableInt _restoredViewMode = RestorableInt(
    CalendarViewMode.week.index,
  );
  final ScrollController _scheduleScrollController = ScrollController();

  late final CalendarController _controller;
  late final bool _ownsController;
  late final CalendarNowProvider _nowProvider;
  late final AnimationController _calendarExpansion;
  Timer? _midnightTimer;
  bool _started = false;
  bool _calendarDragActive = false;
  bool _committingCalendarMode = false;

  @override
  String? get restorationId => 'calendar-page';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nowProvider = widget.nowProvider ?? DateTime.now;
    final injected = widget.controller;
    _controller =
        injected ??
        CalendarController(
          gateway: widget.gateway!,
          timezoneProvider: widget.timezoneProvider!,
          nowProvider: _nowProvider,
        );
    _ownsController = injected == null || widget.disposeInjectedController;
    _calendarExpansion = AnimationController(
      vsync: this,
      value: _controller.state.viewMode == CalendarViewMode.month ? 1 : 0,
    );
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restoredViewMode, 'view-mode');
    if (_started) return;
    _started = true;
    _controller.addListener(_syncRestorableViewMode);
    final restored = _restoredViewMode.value.clamp(
      0,
      CalendarViewMode.values.length - 1,
    );
    unawaited(
      _controller.initialize(
        initialViewMode: CalendarViewMode.values[restored],
      ),
    );
    _scheduleMidnightTimer();
  }

  void _syncRestorableViewMode() {
    final value = _controller.state.viewMode.index;
    if (_restoredViewMode.value != value) _restoredViewMode.value = value;
    if (!_calendarDragActive &&
        !_calendarExpansion.isAnimating &&
        !_committingCalendarMode) {
      _calendarExpansion.value =
          _controller.state.viewMode == CalendarViewMode.month ? 1 : 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.reconcileTemporalContext());
      _scheduleMidnightTimer();
    }
  }

  void _scheduleMidnightTimer() {
    _midnightTimer?.cancel();
    final now = _nowProvider();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final delay = next.difference(now);
    _midnightTimer = Timer(
      delay.isNegative ? const Duration(seconds: 1) : delay,
      () {
        unawaited(_controller.handleMidnight());
        _scheduleMidnightTimer();
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _scheduleScrollController.dispose();
    _calendarExpansion.dispose();
    if (_started) _controller.removeListener(_syncRestorableViewMode);
    if (_ownsController) _controller.dispose();
    _restoredViewMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    return Scaffold(
      key: const ValueKey('calendar-page'),
      backgroundColor: palette.background,
      body: SafeArea(
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = calendarPageHorizontalPadding(
                    constraints.maxWidth,
                  );
                  final state = _controller.state;
                  return Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontal,
                          10,
                          horizontal,
                          0,
                        ),
                        child: CalendarHeader(
                          anchorDate: state.anchorDate,
                          viewMode: state.viewMode,
                          onChooseMonth: _showYearMonthPanel,
                          showToday: !CalendarDateMath.isSameDate(
                            state.selectedDate,
                            state.today,
                          ),
                          onToday: () => unawaited(_controller.goToToday()),
                          onToggleMode: _toggleCalendarMode,
                          onTimeline: _showTimelineUnavailable,
                          onSettings: _showSettingsUnavailable,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: GestureDetector(
                          key: const ValueKey('calendar-upper-gesture-surface'),
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragStart: _handleCalendarDragStart,
                          onVerticalDragUpdate: _handleCalendarDragUpdate,
                          onVerticalDragEnd: _handleCalendarDragEnd,
                          onVerticalDragCancel: _handleCalendarDragCancel,
                          child: CalendarGrid(
                            state: state,
                            expansion: _calendarExpansion,
                            onSelectDate: (date) =>
                                unawaited(_controller.selectDate(date)),
                            onNavigatePeriod: _controller.navigatePeriod,
                          ),
                        ),
                      ),
                      _CalendarResizeHandle(
                        expansion: _calendarExpansion,
                        onTap: _toggleCalendarMode,
                        onVerticalDragStart: _handleCalendarDragStart,
                        onVerticalDragUpdate: _handleCalendarDragUpdate,
                        onVerticalDragEnd: _handleCalendarDragEnd,
                        onVerticalDragCancel: _handleCalendarDragCancel,
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _controller.refresh,
                          child: CustomScrollView(
                            key: const PageStorageKey(
                              'calendar-schedule-scroll',
                            ),
                            controller: _scheduleScrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  horizontal,
                                  0,
                                  horizontal,
                                  CalendarSpacing.contentBottom,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: CalendarSections(
                                    state: state,
                                    onOpenEvent: _openEvent,
                                    onOpenHabit: _openHabit,
                                    onOpenAnniversary: _openAnniversary,
                                    onLoadMore: (section) => unawaited(
                                      _controller.loadMore(section),
                                    ),
                                    onRetryFull: () =>
                                        unawaited(_controller.refresh()),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              right: 36,
              bottom: 24,
              child: AddTaskButton(
                key: const ValueKey('calendar-create-fab'),
                semanticLabel: '新建日程、习惯或纪念日',
                onPressed: _showCreateSheet,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCalendarDragStart(DragStartDetails details) {
    if (_committingCalendarMode) return;
    _calendarDragActive = true;
    _calendarExpansion.stop();
  }

  void _handleCalendarDragUpdate(DragUpdateDetails details) {
    if (_committingCalendarMode) return;
    final next =
        _calendarExpansion.value + details.delta.dy / _calendarDragExtent;
    _calendarExpansion.value = next.clamp(0.0, 1.0);
  }

  void _handleCalendarDragEnd(DragEndDetails details) {
    if (_committingCalendarMode) return;
    final velocity = details.primaryVelocity ?? 0;
    final target = velocity.abs() >= _verticalVelocityThreshold
        ? (velocity > 0 ? 1.0 : 0.0)
        : (_calendarExpansion.value >= 0.5 ? 1.0 : 0.0);
    unawaited(_settleCalendarExpansion(target));
  }

  void _handleCalendarDragCancel() {
    if (_committingCalendarMode) return;
    final target = _controller.state.viewMode == CalendarViewMode.month
        ? 1.0
        : 0.0;
    unawaited(_settleCalendarExpansion(target));
  }

  void _toggleCalendarMode() {
    if (_committingCalendarMode) return;
    final target = _calendarExpansion.value >= 0.5 ? 0.0 : 1.0;
    unawaited(_settleCalendarExpansion(target));
  }

  Future<void> _settleCalendarExpansion(double target) async {
    _calendarDragActive = false;
    final reducedMotion = CalendarMotion.isReduced(context);
    if (reducedMotion) {
      _calendarExpansion.value = target;
    } else {
      final remaining = (target - _calendarExpansion.value).abs();
      final milliseconds = (CalendarMotion.collapse.inMilliseconds * remaining)
          .round()
          .clamp(120, CalendarMotion.collapse.inMilliseconds);
      await _calendarExpansion.animateTo(
        target,
        duration: Duration(milliseconds: milliseconds),
        curve: CalendarMotion.standard,
      );
    }
    if (!mounted) return;
    final mode = target == 1 ? CalendarViewMode.month : CalendarViewMode.week;
    _committingCalendarMode = true;
    try {
      await _controller.setViewMode(mode);
    } finally {
      _committingCalendarMode = false;
    }
    if (!mounted || _controller.state.viewMode == mode) return;
    _calendarExpansion.value =
        _controller.state.viewMode == CalendarViewMode.month ? 1 : 0;
  }

  Future<void> _showYearMonthPanel() async {
    final state = _controller.state;
    final result = await showGeneralDialog<_YearMonthValue>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭年月选择',
      barrierColor: Colors.black54,
      transitionDuration: CalendarMotion.effective(
        context,
        CalendarMotion.panel,
      ),
      pageBuilder: (context, animation, secondaryAnimation) => _YearMonthPanel(
        initialYear: state.anchorDate.year,
        initialMonth: state.anchorDate.month,
        today: state.today,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: CalendarMotion.enter,
            ),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: CalendarMotion.enter,
                    ),
                  ),
              child: child,
            ),
          ),
    );
    if (!mounted || result == null) return;
    if (result.isToday) {
      await _controller.goToToday();
      return;
    }
    await _controller.jumpToMonth(year: result.year, month: result.month);
  }

  void _showTimelineUnavailable() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('时间线视图暂未开放')));
  }

  void _showSettingsUnavailable() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日历设置暂未开放')));
  }

  Future<void> _showCreateSheet() async {
    final target = await showModalBottomSheet<CalendarCreateTarget>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: const ListTile(
                title: Text('新建安排'),
                subtitle: Text('选择要添加到日历的内容'),
              ),
            ),
            _CreateChoice(
              key: const ValueKey('calendar-create-event'),
              icon: Icons.schedule_rounded,
              title: '日程',
              subtitle: '安排会议、任务或全天事项',
              onTap: () =>
                  Navigator.pop(sheetContext, CalendarCreateTarget.event),
            ),
            _CreateChoice(
              key: const ValueKey('calendar-create-habit'),
              icon: Icons.track_changes_rounded,
              title: '习惯',
              subtitle: '开始一段持续挑战',
              onTap: () =>
                  Navigator.pop(sheetContext, CalendarCreateTarget.habit),
            ),
            _CreateChoice(
              key: const ValueKey('calendar-create-anniversary'),
              icon: Icons.celebration_rounded,
              title: '纪念日',
              subtitle: '记录值得记住的日期',
              onTap: () =>
                  Navigator.pop(sheetContext, CalendarCreateTarget.anniversary),
            ),
          ],
        ),
      ),
    );
    if (!mounted || target == null) return;
    final callback = widget.onCreateItem;
    if (callback == null) {
      _showUnavailable('新建页面暂不可用');
      return;
    }
    final state = _controller.state;
    final initialDate =
        target == CalendarCreateTarget.habit &&
            state.selectedDate.isBefore(state.today)
        ? state.today
        : state.selectedDate;
    _controller.beginRouteTransition();
    final changed = await callback(context, target, initialDate);
    if (!mounted) return;
    await _controller.handleRouteResult(changed == true);
  }

  Future<void> _openEvent(CalendarEventItemDto item) async {
    final callback = widget.onOpenEvent;
    if (callback == null) {
      _showUnavailable('日程详情暂不可用');
      return;
    }
    _controller.beginRouteTransition();
    final changed = await callback(context, item);
    if (mounted) await _controller.handleRouteResult(changed != false);
  }

  Future<void> _openHabit(CalendarHabitItemDto item) async {
    final callback = widget.onOpenHabit;
    if (callback == null) {
      _showUnavailable('习惯详情暂不可用');
      return;
    }
    _controller.beginRouteTransition();
    final changed = await callback(context, item);
    if (mounted) await _controller.handleRouteResult(changed != false);
  }

  Future<void> _openAnniversary(CalendarAnniversaryItemDto item) async {
    final callback = widget.onOpenAnniversary;
    if (callback == null) {
      _showUnavailable('纪念日详情暂不可用');
      return;
    }
    _controller.beginRouteTransition();
    final changed = await callback(context, item);
    if (mounted) await _controller.handleRouteResult(changed != false);
  }

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CalendarResizeHandle extends StatelessWidget {
  const _CalendarResizeHandle({
    required this.expansion,
    required this.onTap,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
  });

  final Animation<double> expansion;
  final VoidCallback onTap;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final GestureDragCancelCallback onVerticalDragCancel;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: expansion,
    builder: (context, _) => Semantics(
      button: true,
      label: '调整日历高度',
      value: expansion.value >= 0.5 ? '已展开' : '已收起',
      hint: '上下拖动，或双击切换日历高度',
      child: GestureDetector(
        key: const ValueKey('calendar-resize-handle'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onVerticalDragStart: onVerticalDragStart,
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,
        onVerticalDragCancel: onVerticalDragCancel,
        child: SizedBox(
          height: 28,
          child: Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.34),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CreateChoice extends StatelessWidget {
  const _CreateChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 64,
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}

class _YearMonthValue {
  const _YearMonthValue(this.year, this.month) : isToday = false;
  const _YearMonthValue.today() : year = 0, month = 0, isToday = true;

  final int year;
  final int month;
  final bool isToday;
}

class _YearMonthPanel extends StatefulWidget {
  const _YearMonthPanel({
    required this.initialYear,
    required this.initialMonth,
    required this.today,
  });

  final int initialYear;
  final int initialMonth;
  final DateTime today;

  @override
  State<_YearMonthPanel> createState() => _YearMonthPanelState();
}

class _YearMonthPanelState extends State<_YearMonthPanel> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一年',
                      onPressed: _year > 1900
                          ? () => setState(() => _year -= 1)
                          : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '$_year年',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '下一年',
                      onPressed: _year < 2100
                          ? () => setState(() => _year += 1)
                          : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('calendar-month-panel-today'),
                    onPressed: () =>
                        Navigator.pop(context, const _YearMonthValue.today()),
                    icon: const Icon(Icons.today_rounded),
                    label: Text(
                      '今天 · ${widget.today.month}月${widget.today.day}日',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 12,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.1,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, index) {
                    final month = index + 1;
                    final selected =
                        _year == widget.initialYear &&
                        month == widget.initialMonth;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: '$_year年$month月',
                      child: selected
                          ? FilledButton(
                              onPressed: () => Navigator.pop(
                                context,
                                _YearMonthValue(_year, month),
                              ),
                              child: Text('$month月'),
                            )
                          : OutlinedButton(
                              onPressed: () => Navigator.pop(
                                context,
                                _YearMonthValue(_year, month),
                              ),
                              child: Text('$month月'),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

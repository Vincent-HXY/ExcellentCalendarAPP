import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/calendar/calendar_controller.dart';
import '../../application/calendar/calendar_date_math.dart';
import '../../gateway_interfaces/calendar_gateway.dart';
import '../../native_contract/calendar/calendar_response_dtos.dart';
import 'calendar_design_tokens.dart';
import 'calendar_gesture_state_machine.dart';
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
    with RestorationMixin, WidgetsBindingObserver {
  final RestorableInt _restoredViewMode = RestorableInt(
    CalendarViewMode.week.index,
  );
  final ScrollController _scrollController = ScrollController();
  final CalendarGestureStateMachine _gesture = CalendarGestureStateMachine();

  late final CalendarController _controller;
  late final bool _ownsController;
  late final CalendarNowProvider _nowProvider;
  Timer? _midnightTimer;
  bool _started = false;
  bool _fabExtended = true;
  int _transitionDirection = 1;
  int? _gesturePointer;

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
    _scrollController.addListener(_handleScroll);
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
  }

  void _handleScroll() {
    final extended =
        !_scrollController.hasClients || _scrollController.offset < 120;
    if (extended != _fabExtended && mounted) {
      setState(() => _fabExtended = extended);
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
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    if (_started) _controller.removeListener(_syncRestorableViewMode);
    if (_ownsController) _controller.dispose();
    _restoredViewMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    final compactForAccessibility =
        MediaQuery.textScalerOf(context).scale(1) > 1.35;
    final createAction = _buildCreateAction(
      extended: _fabExtended && !compactForAccessibility,
    );
    return Scaffold(
      key: const ValueKey('calendar-page'),
      backgroundColor: palette.background,
      bottomNavigationBar: Material(
        key: const ValueKey('calendar-create-action-bar'),
        color: palette.background,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SizedBox(
            height: 60,
            child: Align(alignment: Alignment.centerRight, child: createAction),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = calendarPageHorizontalPadding(
                constraints.maxWidth,
              );
              final state = _controller.state;
              return Listener(
                key: const ValueKey('calendar-gesture-surface'),
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  if (_gesturePointer != null) return;
                  _gesturePointer = event.pointer;
                  _gesture.start(
                    mode: state.viewMode,
                    atContentTop:
                        !_scrollController.hasClients ||
                        _scrollController.offset <= 0,
                  );
                },
                onPointerMove: (event) {
                  if (_gesturePointer != event.pointer) return;
                  _gesture.update(dx: event.delta.dx, dy: event.delta.dy);
                },
                onPointerUp: (event) {
                  if (_gesturePointer != event.pointer) return;
                  _gesturePointer = null;
                  unawaited(_handleGestureEnd());
                },
                onPointerCancel: (event) {
                  if (_gesturePointer != event.pointer) return;
                  _gesturePointer = null;
                  _gesture.cancel();
                },
                child: CustomScrollView(
                  key: const PageStorageKey('calendar-content-scroll'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        10,
                        horizontal,
                        CalendarSpacing.contentBottom,
                      ),
                      sliver: SliverList.list(
                        children: [
                          CalendarHeader(
                            anchorDate: state.anchorDate,
                            viewMode: state.viewMode,
                            onPrevious: () => _navigate(-1),
                            onNext: () => _navigate(1),
                            onChooseMonth: _showYearMonthPanel,
                            showToday: !CalendarDateMath.isSameDate(
                              state.selectedDate,
                              state.today,
                            ),
                            onToday: () => unawaited(_controller.goToToday()),
                            onToggleMode: () => unawaited(
                              _controller.setViewMode(
                                state.viewMode == CalendarViewMode.week
                                    ? CalendarViewMode.month
                                    : CalendarViewMode.week,
                              ),
                            ),
                            onTimeline: _showTimelineUnavailable,
                            onSettings: _showSettingsUnavailable,
                          ),
                          const SizedBox(height: 12),
                          CalendarGrid(
                            state: state,
                            transitionDirection: _transitionDirection,
                            onSelectDate: (date) =>
                                unawaited(_controller.selectDate(date)),
                          ),
                          CalendarSections(
                            state: state,
                            onOpenEvent: _openEvent,
                            onOpenHabit: _openHabit,
                            onOpenAnniversary: _openAnniversary,
                            onLoadMore: (section) =>
                                unawaited(_controller.loadMore(section)),
                            onRetryFull: () => unawaited(_controller.refresh()),
                            onCreate: _showCreateSheet,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCreateAction({required bool extended}) => Semantics(
    button: true,
    label: '新建日程、习惯或纪念日',
    child: extended
        ? FloatingActionButton.extended(
            key: const ValueKey('calendar-create-fab'),
            onPressed: _showCreateSheet,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建'),
          )
        : FloatingActionButton(
            key: const ValueKey('calendar-create-fab'),
            tooltip: '新建安排',
            onPressed: _showCreateSheet,
            child: const Icon(Icons.add_rounded),
          ),
  );

  void _navigate(int delta) {
    setState(() => _transitionDirection = delta.sign);
    unawaited(_controller.navigatePeriod(delta));
  }

  Future<void> _handleGestureEnd() async {
    final action = _gesture.end();
    switch (action) {
      case CalendarGestureAction.previousPeriod:
        _navigate(-1);
      case CalendarGestureAction.nextPeriod:
        _navigate(1);
      case CalendarGestureAction.collapse:
        await _controller.setViewMode(CalendarViewMode.week);
      case CalendarGestureAction.expand:
        await _controller.setViewMode(CalendarViewMode.month);
      case CalendarGestureAction.refresh:
        _gesture.markRefreshing();
        await _controller.refresh();
      case null:
        break;
    }
    _gesture.settle();
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

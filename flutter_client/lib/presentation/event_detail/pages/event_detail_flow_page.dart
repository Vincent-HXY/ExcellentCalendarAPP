import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/event/complete_event_use_case.dart';
import '../../../application/event/recurring_event_detail_controller.dart';
import '../../../application/event/update_event_use_case.dart';
import '../../../application/timezone/timezone_application_service.dart';
import '../../../gateway_interfaces/category_repository.dart';
import '../../../native_contract/event/complete_event_request_dto.dart';
import '../../../native_contract/recurrence/recurrence_response_dto.dart';
import '../../new_schedule/edit_recurring_event_page.dart';
import '../event_detail_design_tokens.dart';
import '../event_detail_formatters.dart';
import '../models/event_detail_ui_state.dart';
import '../widgets/event_meta_grid_card.dart';
import '../widgets/event_note_card.dart';
import '../widgets/event_schedule_card.dart';
import '../widgets/event_summary_card.dart';
import 'event_detail_page.dart';

/// Loads an Event from the native core and selects the ordinary or recurring
/// detail experience from the returned contract projection.
class EventDetailFlowPage extends StatefulWidget {
  const EventDetailFlowPage({
    required this.controller,
    required this.completeEventUseCase,
    required this.updateEventUseCase,
    required this.timezoneService,
    required this.categoryRepository,
    this.loadOnInit = true,
    this.disposeController = true,
    super.key,
  });

  final RecurringEventDetailController controller;
  final CompleteEventUseCase completeEventUseCase;
  final UpdateEventUseCase updateEventUseCase;
  final TimezoneApplicationService timezoneService;
  final CategoryRepository categoryRepository;

  /// Exposed for deterministic widget tests. Production routes keep this true.
  final bool loadOnInit;
  final bool disposeController;

  @override
  State<EventDetailFlowPage> createState() => _EventDetailFlowPageState();
}

class _EventDetailFlowPageState extends State<EventDetailFlowPage> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) unawaited(widget.controller.load());
  }

  @override
  void didUpdateWidget(covariant EventDetailFlowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.disposeController) oldWidget.controller.dispose();
      if (widget.loadOnInit) unawaited(widget.controller.load());
    }
  }

  @override
  void dispose() {
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        if (state.phase == RecurringEventDetailPhase.idle ||
            state.phase == RecurringEventDetailPhase.loading) {
          return const _DetailLoadScaffold();
        }
        if (state.phase == RecurringEventDetailPhase.failure ||
            state.detail == null ||
            state.localizedEventTimeRange == null ||
            state.referenceLocalNow == null) {
          return _DetailLoadScaffold(
            message: state.loadFailure?.message ?? '无法加载日程详情',
            onRetry: widget.controller.load,
          );
        }

        if (!state.isRecurring) {
          final detail = state.detail!;
          final uiState = EventDetailUiState.fromEvent(
            detail.event,
            localizedTimeRange: state.localizedEventTimeRange!,
            referenceLocalNow: state.referenceLocalNow,
            reminders: [
              for (final reminder in detail.reminders)
                ReminderUiModel(
                  advanceMinutes: reminder.advanceMinutes,
                  remindAt: reminder.remindAt,
                ),
            ],
            category: detail.category,
          );
          return EventDetailPage(
            state: uiState,
            canComplete: detail.event.status == 'active',
            onComplete: () => _completeOrdinaryEvent(detail.event.id),
          );
        }

        return RecurringEventDetailPage(
          key: ValueKey(state.detail!.event.id),
          controller: widget.controller,
          state: state,
          updateEventUseCase: widget.updateEventUseCase,
          timezoneService: widget.timezoneService,
          categoryRepository: widget.categoryRepository,
        );
      },
    );
  }

  Future<EventDetailCompletionResult> _completeOrdinaryEvent(
    String eventId,
  ) async {
    try {
      final invocation = await widget.completeEventUseCase.execute(
        CompleteEventRequestDto(eventId: eventId, source: 'manual'),
      );
      if (invocation.result.ok) {
        return const EventDetailCompletionResult.success();
      }
      return EventDetailCompletionResult.failure(
        invocation.result.error?.message ?? '完成日程失败，请稍后重试',
      );
    } catch (_) {
      return const EventDetailCompletionResult.failure('完成日程失败，请稍后重试');
    }
  }
}

class RecurringEventDetailPage extends StatefulWidget {
  const RecurringEventDetailPage({
    required this.controller,
    required this.state,
    required this.updateEventUseCase,
    required this.timezoneService,
    required this.categoryRepository,
    super.key,
  });

  final RecurringEventDetailController controller;
  final RecurringEventDetailState state;
  final UpdateEventUseCase updateEventUseCase;
  final TimezoneApplicationService timezoneService;
  final CategoryRepository categoryRepository;

  @override
  State<RecurringEventDetailPage> createState() =>
      _RecurringEventDetailPageState();
}

class _RecurringEventDetailPageState extends State<RecurringEventDetailPage> {
  final _focusedOccurrenceKey = GlobalKey();
  var _didRevealFocusedOccurrence = false;

  @override
  void didUpdateWidget(covariant RecurringEventDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.focusOccurrenceKey != widget.state.focusOccurrenceKey) {
      _didRevealFocusedOccurrence = false;
    }
    _scheduleRevealFocusedOccurrence();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRevealFocusedOccurrence();
    final detail = widget.state.detail!;
    final event = detail.event;
    final uiState = EventDetailUiState.fromEvent(
      event,
      localizedTimeRange: widget.state.localizedEventTimeRange!,
      referenceLocalNow: widget.state.referenceLocalNow,
      displayStatusOverride: event.status == 'active'
          ? EventDisplayStatus.inProgress
          : null,
      reminders: [
        for (final reminder in detail.reminders)
          ReminderUiModel(
            advanceMinutes: reminder.advanceMinutes,
            remindAt: reminder.remindAt,
          ),
      ],
      category: detail.category,
    );
    final isBusy = widget.state.hasMutationInProgress;
    final isActive = event.status == 'active';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: EventDetailColors.backgroundMiddle,
        appBar: AppBar(
          backgroundColor: EventDetailColors.backgroundStart,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: const Text('重复日程详情'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          actions: [
            IconButton(
              key: const ValueKey('manage-series-top'),
              tooltip: '管理整个系列',
              onPressed: isBusy ? null : _showSeriesActions,
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      EventDetailColors.backgroundStart,
                      EventDetailColors.backgroundMiddle,
                      EventDetailColors.backgroundEnd,
                    ],
                  ),
                ),
              ),
            ),
            RefreshIndicator(
              onRefresh: widget.controller.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  EventDetailSpacing.pageHorizontal,
                  12,
                  EventDetailSpacing.pageHorizontal,
                  28,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: EventDetailSpacing.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.state.isRefreshing)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                color: EventDetailColors.primaryTeal,
                              ),
                            ),
                          if (widget.state.loadFailure != null)
                            _InlineFailureCard(
                              message: widget.state.loadFailure!.message,
                              onRetry: widget.controller.refresh,
                            ),
                          EventSummaryCard(state: uiState),
                          const _SectionTitle('重复规则'),
                          _RecurrenceRuleCard(
                            recurrence: detail.recurrence!,
                            status: event.status,
                          ),
                          const _SectionTitle('时间安排'),
                          EventScheduleCard(
                            state: uiState,
                            onEditField: isActive && !isBusy
                                ? (_) => _openSeriesEditor()
                                : null,
                          ),
                          if ((event.content ?? '').isNotEmpty) ...[
                            const _SectionTitle('详情与备注'),
                            EventNoteCard(
                              state: uiState,
                              onTap: isActive && !isBusy
                                  ? _openSeriesEditor
                                  : null,
                            ),
                          ],
                          const _SectionTitle('系列状态'),
                          EventMetaGridCard(state: uiState),
                          const _SectionTitle('最近与即将发生'),
                          _OccurrenceList(
                            state: widget.state,
                            seriesIsActive: isActive,
                            focusedOccurrenceKey: _focusedOccurrenceKey,
                            onComplete: (key) => _runOccurrenceAction(
                              () => widget.controller.completeOccurrence(key),
                              successMessage: '已完成本次日程',
                            ),
                            onReopen: (key) => _runOccurrenceAction(
                              () => widget.controller.reopenOccurrence(key),
                              successMessage: '已重新打开本次日程',
                            ),
                            onSkip: (key) => _runOccurrenceAction(
                              () => widget.controller.skipOccurrence(key),
                              successMessage: '已跳过本次日程',
                            ),
                            onCancel: (key) =>
                                _confirmOccurrenceCancellation(key),
                            onLoadMore: widget.controller.loadMore,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _SeriesActionBar(
          isBusy: isBusy,
          canEdit: isActive,
          onEdit: _openSeriesEditor,
          onManage: _showSeriesActions,
        ),
      ),
    );
  }

  void _scheduleRevealFocusedOccurrence() {
    final focusKey = widget.state.focusOccurrenceKey;
    if (_didRevealFocusedOccurrence ||
        focusKey == null ||
        !widget.state.occurrences.any(
          (item) => item.occurrenceKey == focusKey,
        )) {
      return;
    }
    _didRevealFocusedOccurrence = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _focusedOccurrenceKey.currentContext;
      if (!mounted || targetContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: .2,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  Future<void> _openSeriesEditor() async {
    if (widget.state.hasMutationInProgress ||
        widget.state.detail!.event.status != 'active') {
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EditRecurringEventPage(
          detail: widget.state.detail!,
          updateUseCase: widget.updateEventUseCase,
          timezoneService: widget.timezoneService,
          categoryRepository: widget.categoryRepository,
        ),
      ),
    );
    if (!mounted || updated != true) return;
    await widget.controller.refresh();
    if (!mounted) return;
    final failure = widget.controller.state.loadFailure;
    _showMessage(failure?.message ?? '整个重复系列已更新');
  }

  Future<void> _runOccurrenceAction(
    Future<RecurringEventActionResult> Function() action, {
    required String successMessage,
  }) async {
    final result = await action();
    if (!mounted) return;
    _showActionResult(result, successMessage: successMessage);
  }

  Future<void> _confirmOccurrenceCancellation(String occurrenceKey) async {
    final confirmed = await _confirm(
      title: '取消本次日程？',
      message: '只取消这一次，不会结束整个重复系列。之后可以重新打开本次日程。',
      confirmLabel: '取消本次',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runOccurrenceAction(
      () => widget.controller.cancelOccurrence(occurrenceKey),
      successMessage: '已取消本次日程',
    );
  }

  Future<void> _showSeriesActions() async {
    if (widget.state.hasMutationInProgress) return;
    final status = widget.state.detail!.event.status;
    final command = await showModalBottomSheet<_SeriesCommand>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  '管理整个重复系列',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('系列操作不会只作用于当前这一次'),
              ),
              if (status == 'active')
                ListTile(
                  key: const ValueKey('complete-series-action'),
                  leading: const Icon(Icons.task_alt_rounded),
                  title: const Text('完成整个系列'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _SeriesCommand.complete),
                ),
              if (status == 'completed')
                ListTile(
                  key: const ValueKey('reopen-series-action'),
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('重新打开整个系列'),
                  subtitle: const Text('从现在之后的第一个合法日程实例开始'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _SeriesCommand.reopen),
                ),
              if (status == 'active')
                ListTile(
                  key: const ValueKey('cancel-series-action'),
                  leading: const Icon(Icons.block_rounded),
                  title: const Text('取消整个系列'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _SeriesCommand.cancel),
                ),
              ListTile(
                key: const ValueKey('delete-series-action'),
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  '删除整个系列',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.pop(sheetContext, _SeriesCommand.delete),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || command == null) return;
    await _runSeriesCommand(command);
  }

  Future<void> _runSeriesCommand(_SeriesCommand command) async {
    final prompt = switch (command) {
      _SeriesCommand.complete => (
        title: '完成整个系列？',
        message: '整个系列会停止继续提醒。你之后仍可重新打开系列。',
        confirm: '完成系列',
        destructive: false,
      ),
      _SeriesCommand.reopen => (
        title: '重新打开整个系列？',
        message: '将从当前时间之后的第一个合法日程实例继续，不会补发更早的提醒。',
        confirm: '重新打开',
        destructive: false,
      ),
      _SeriesCommand.cancel => (
        title: '取消整个系列？',
        message: '所有后续 occurrence 与提醒都会停止。',
        confirm: '取消系列',
        destructive: true,
      ),
      _SeriesCommand.delete => (
        title: '删除整个系列？',
        message: '整个重复系列都会被删除，此操作不能只保留某一次。',
        confirm: '删除系列',
        destructive: true,
      ),
    };
    final confirmed = await _confirm(
      title: prompt.title,
      message: prompt.message,
      confirmLabel: prompt.confirm,
      destructive: prompt.destructive,
    );
    if (!confirmed || !mounted) return;

    final result = await switch (command) {
      _SeriesCommand.complete => widget.controller.completeSeries(),
      _SeriesCommand.reopen => widget.controller.reopenSeries(),
      _SeriesCommand.cancel => widget.controller.cancelSeries(),
      _SeriesCommand.delete => widget.controller.deleteSeries(),
    };
    if (!mounted) return;
    if (result.succeeded && command == _SeriesCommand.delete) {
      _showActionResult(result, successMessage: '整个重复系列已删除');
      await Navigator.maybePop(context, true);
      return;
    }
    final successMessage = switch (command) {
      _SeriesCommand.complete => '整个重复系列已完成',
      _SeriesCommand.reopen => '整个重复系列已重新打开',
      _SeriesCommand.cancel => '整个重复系列已取消',
      _SeriesCommand.delete => '整个重复系列已删除',
    };
    _showActionResult(result, successMessage: successMessage);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required bool destructive,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Colors.redAccent)
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showActionResult(
    RecurringEventActionResult result, {
    required String successMessage,
  }) {
    final message = result.succeeded
        ? result.warning?.message ?? successMessage
        : result.failure?.message ?? '操作失败，请稍后重试';
    _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DetailLoadScaffold extends StatelessWidget {
  const _DetailLoadScaffold({this.message, this.onRetry});

  final String? message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventDetailColors.backgroundMiddle,
      appBar: AppBar(
        backgroundColor: EventDetailColors.backgroundStart,
        surfaceTintColor: Colors.transparent,
        title: const Text('日程详情'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: message == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('正在加载日程详情…'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_busy_rounded,
                      size: 44,
                      color: EventDetailColors.secondaryText,
                    ),
                    const SizedBox(height: 12),
                    Text(message!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const ValueKey('retry-event-detail'),
                      onPressed: onRetry == null
                          ? null
                          : () => unawaited(onRetry!()),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RecurrenceRuleCard extends StatelessWidget {
  const _RecurrenceRuleCard({required this.recurrence, required this.status});

  final RecurrenceResponseDto recurrence;
  final String status;

  @override
  Widget build(BuildContext context) {
    final frequency = switch (recurrence.frequency) {
      'daily' => '每天',
      'weekly' => '每周 · ${_weekdayLabel(recurrence.daysOfWeek.single)}',
      'monthly' => '每月 · ${recurrence.dayOfMonth} 日',
      _ => recurrence.frequency,
    };
    final statusLabel = switch (status) {
      'active' => '持续有效',
      'completed' => '系列已完成',
      'cancelled' => '系列已取消',
      'archived' => '系列已归档',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: eventDetailCardDecoration(),
      child: Column(
        children: [
          _RuleRow(icon: Icons.repeat_rounded, label: '频率', value: frequency),
          const Divider(height: 22, color: EventDetailColors.divider),
          _RuleRow(
            icon: Icons.public_rounded,
            label: '原始时区',
            value: recurrence.timezone,
          ),
          const Divider(height: 22, color: EventDetailColors.divider),
          _RuleRow(
            icon: Icons.all_inclusive_rounded,
            label: '结束条件',
            value: statusLabel,
          ),
          if (recurrence.frequency == 'monthly') ...[
            const Divider(height: 22, color: EventDetailColors.divider),
            const _RuleRow(
              icon: Icons.info_outline_rounded,
              label: '短月份',
              value: '自动使用当月最后一天，锚点不变',
            ),
          ],
        ],
      ),
    );
  }

  static String _weekdayLabel(int weekday) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[weekday - 1];
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: EventDetailColors.primaryTeal),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(label, style: EventDetailTextStyles.timelineLabel),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: EventDetailTextStyles.timelineValue,
          ),
        ),
      ],
    );
  }
}

class _OccurrenceList extends StatelessWidget {
  const _OccurrenceList({
    required this.state,
    required this.seriesIsActive,
    required this.focusedOccurrenceKey,
    required this.onComplete,
    required this.onReopen,
    required this.onSkip,
    required this.onCancel,
    required this.onLoadMore,
  });

  final RecurringEventDetailState state;
  final bool seriesIsActive;
  final GlobalKey focusedOccurrenceKey;
  final ValueChanged<String> onComplete;
  final ValueChanged<String> onReopen;
  final ValueChanged<String> onSkip;
  final ValueChanged<String> onCancel;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (state.occurrences.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: eventDetailCardDecoration(),
        child: const Column(
          children: [
            Icon(
              Icons.event_repeat_rounded,
              color: EventDetailColors.secondaryText,
            ),
            SizedBox(height: 8),
            Text('当前时间窗口内没有日程实例'),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final item in state.occurrences) ...[
          _OccurrenceCard(
            key: item.occurrenceKey == state.focusOccurrenceKey
                ? focusedOccurrenceKey
                : ValueKey(item.occurrenceKey),
            item: item,
            isFocused: item.occurrenceKey == state.focusOccurrenceKey,
            isMutating: state.isOccurrenceMutating(item.occurrenceKey),
            seriesIsActive: seriesIsActive,
            onComplete: () => onComplete(item.occurrenceKey),
            onReopen: () => onReopen(item.occurrenceKey),
            onSkip: () => onSkip(item.occurrenceKey),
            onCancel: () => onCancel(item.occurrenceKey),
          ),
          const SizedBox(height: 10),
        ],
        if (state.paginationFailure != null)
          _InlineFailureCard(
            message: state.paginationFailure!.message,
            onRetry: onLoadMore,
          ),
        if (state.hasMore)
          OutlinedButton.icon(
            key: const ValueKey('load-more-occurrences'),
            onPressed: state.isLoadingMore
                ? null
                : () => unawaited(onLoadMore()),
            icon: state.isLoadingMore
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text(state.isLoadingMore ? '加载中…' : '加载更多日程实例'),
          ),
      ],
    );
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({
    required this.item,
    required this.isFocused,
    required this.isMutating,
    required this.seriesIsActive,
    required this.onComplete,
    required this.onReopen,
    required this.onSkip,
    required this.onCancel,
    super.key,
  });

  final RecurringEventOccurrenceItem item;
  final bool isFocused;
  final bool isMutating;
  final bool seriesIsActive;
  final VoidCallback onComplete;
  final VoidCallback onReopen;
  final VoidCallback onSkip;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final start = item.localizedTimeRange.start.toComponentDateTime();
    final end = item.localizedTimeRange.end.toComponentDateTime();
    final isAllDay = item.occurrence.occurrenceStartDate != null;
    final statusPresentation = _occurrenceStatus(item.status);
    final canMutate = seriesIsActive && !isMutating;
    final isTerminal = item.status != 'scheduled';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EventDetailColors.cardBackground,
        borderRadius: BorderRadius.circular(EventDetailSizes.cardRadius),
        border: isFocused
            ? Border.all(color: EventDetailColors.primaryTeal, width: 1.5)
            : null,
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A6F8790),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: EventDetailColors.primaryTealLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${start.month}月',
                      style: const TextStyle(
                        color: EventDetailColors.primaryTealDark,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      start.day.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        color: EventDetailColors.primaryTealDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 7,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${formatEventDate(start)} · ${eventWeekdayLabel(start)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: EventDetailColors.primaryText,
                          ),
                        ),
                        if (isFocused)
                          const _CompactPill(
                            label: '通知定位',
                            foreground: EventDetailColors.primaryTealDark,
                            background: EventDetailColors.primaryTealLight,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAllDay
                          ? _allDayRangeLabel(start, end)
                          : '${formatEventTime(start)} – ${formatEventTime(end)} · ${item.occurrence.timezone}',
                      style: EventDetailTextStyles.timelineLabel,
                    ),
                  ],
                ),
              ),
              _CompactPill(
                label: statusPresentation.label,
                foreground: statusPresentation.foreground,
                background: statusPresentation.background,
              ),
            ],
          ),
          if (seriesIsActive) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: EventDetailColors.divider),
            const SizedBox(height: 10),
            if (isMutating)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (isTerminal)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  key: ValueKey('reopen-occurrence-${item.occurrenceKey}'),
                  onPressed: canMutate ? onReopen : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('重新打开本次'),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PopupMenuButton<_OccurrenceCommand>(
                    key: ValueKey('more-occurrence-${item.occurrenceKey}'),
                    enabled: canMutate,
                    tooltip: '更多本次操作',
                    onSelected: (command) {
                      switch (command) {
                        case _OccurrenceCommand.skip:
                          onSkip();
                        case _OccurrenceCommand.cancel:
                          onCancel();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _OccurrenceCommand.skip,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.skip_next_rounded),
                          title: Text('跳过本次'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _OccurrenceCommand.cancel,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.block_rounded),
                          title: Text('取消本次'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    key: ValueKey('complete-occurrence-${item.occurrenceKey}'),
                    onPressed: canMutate ? onComplete : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('完成本次'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  static String _allDayRangeLabel(DateTime start, DateTime endExclusive) {
    final lastDay = endExclusive.subtract(const Duration(days: 1));
    if (start.year == lastDay.year &&
        start.month == lastDay.month &&
        start.day == lastDay.day) {
      return '全天 · 原始时区日期';
    }
    return '全天 · ${formatEventDate(start)} – ${formatEventDate(lastDay)}';
  }
}

class _CompactPill extends StatelessWidget {
  const _CompactPill({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InlineFailureCard extends StatelessWidget {
  const _InlineFailureCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EventDetailColors.warningBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: EventDetailColors.warningOrange,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(
            onPressed: () => unawaited(onRetry()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class _SeriesActionBar extends StatelessWidget {
  const _SeriesActionBar({
    required this.isBusy,
    required this.canEdit,
    required this.onEdit,
    required this.onManage,
  });

  final bool isBusy;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDFDFD),
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('edit-whole-series'),
                  onPressed: !isBusy && canEdit ? onEdit : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改整个系列'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('manage-whole-series'),
                  onPressed: isBusy ? null : onManage,
                  icon: isBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.tune_rounded),
                  label: Text(isBusy ? '处理中…' : '管理系列'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: EventDetailSpacing.sectionTop,
        bottom: EventDetailSpacing.sectionToCard,
      ),
      child: Text(label, style: EventDetailTextStyles.sectionTitle),
    );
  }
}

({String label, Color foreground, Color background}) _occurrenceStatus(
  String status,
) {
  return switch (status) {
    'completed' => (
      label: '已完成',
      foreground: const Color(0xFF23805E),
      background: const Color(0xFFE1F5EC),
    ),
    'skipped' => (
      label: '已跳过',
      foreground: const Color(0xFF6B7280),
      background: const Color(0xFFF0F1F3),
    ),
    'cancelled' => (
      label: '已取消',
      foreground: const Color(0xFFB54747),
      background: const Color(0xFFFBEAEA),
    ),
    _ => (
      label: '待处理',
      foreground: EventDetailColors.warningOrange,
      background: EventDetailColors.warningBackground,
    ),
  };
}

enum _OccurrenceCommand { skip, cancel }

enum _SeriesCommand { complete, reopen, cancel, delete }

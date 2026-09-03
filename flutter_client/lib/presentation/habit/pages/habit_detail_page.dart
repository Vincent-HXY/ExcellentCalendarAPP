import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/bootstrap/notification_permission_controller.dart';
import '../../../app/routing/app_router.dart';
import '../../../application/habit/habit_detail_controller.dart';
import '../../../application/habit/habit_form_controller.dart';
import '../../../application/habit/habit_models.dart';
import '../../../gateway_interfaces/category_repository.dart';
import '../../../gateway_interfaces/habit_gateway.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../../../native_contract/habit/habit_response_dtos.dart';
import '../habit_design.dart';
import 'habit_day_page.dart';
import 'habit_form_page.dart';

class HabitDetailPage extends StatefulWidget {
  const HabitDetailPage({
    required this.habitId,
    required this.gateway,
    required this.timezoneProvider,
    required this.categoryRepository,
    this.permissionController,
    this.focusOccurrenceKey,
    this.focusDate,
    super.key,
  });
  final String habitId;
  final String? focusOccurrenceKey;
  final String? focusDate;
  final HabitGateway gateway;
  final String Function() timezoneProvider;
  final CategoryRepository categoryRepository;
  final NotificationPermissionController? permissionController;

  @override
  State<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends State<HabitDetailPage>
    with WidgetsBindingObserver {
  late final HabitDetailController _controller;
  final List<HabitDailyStatusResponseDto> _earlier = [];
  bool _loadingEarlier = false;
  bool _changed = false;
  bool _isPopping = false;
  HabitScheduleCapabilityResponseDto? _latestScheduleCapability;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = HabitDetailController(
      habitId: widget.habitId,
      focusOccurrenceKey: widget.focusOccurrenceKey,
      gateway: widget.gateway,
      timezoneProvider: widget.timezoneProvider,
    );
    unawaited(_controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.load(preserve: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openDay(String date) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => HabitDayPage(
          habitId: widget.habitId,
          date: date,
          gateway: widget.gateway,
          timezoneProvider: widget.timezoneProvider,
        ),
      ),
    );
    if (changed != false) _changed = true;
    if (mounted) unawaited(_controller.load(preserve: true));
  }

  Future<void> _edit(HabitDetailViewData detail) async {
    HabitFormSubmitOutcome? outcome;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HabitFormPage(
          gateway: widget.gateway,
          timezoneProvider: widget.timezoneProvider,
          categoryRepository: widget.categoryRepository,
          permissionController: widget.permissionController,
          initialDetail: detail.dto,
          onSubmitted: (value) => outcome = value,
        ),
      ),
    );
    if (mounted) {
      final submitted = outcome;
      if (submitted != null) {
        _changed = true;
        setState(() => _latestScheduleCapability = submitted.capability);
      }
      unawaited(_controller.load(preserve: true));
    }
  }

  Future<void> _restart(HabitDetailViewData detail) async {
    final seed = HabitFormSeed(
      title: detail.habit.title,
      description: detail.habit.description ?? '',
      categoryId: detail.habit.categoryId,
      quantitative: detail.habit.isQuantitative,
      targetText: detail.habit.targetCountHundredths == null
          ? ''
          : formatHundredths(detail.habit.targetCountHundredths!),
      unit: detail.habit.unit ?? '',
    );
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HabitFormPage(
          gateway: widget.gateway,
          timezoneProvider: widget.timezoneProvider,
          categoryRepository: widget.categoryRepository,
          permissionController: widget.permissionController,
          seed: seed,
        ),
      ),
    );
    if (changed == true) _changed = true;
  }

  Future<void> _end() async {
    final confirmed = await _confirm(
      title: '提前结束挑战？',
      body: '结束后不可恢复，历史会保留并变为只读。',
      action: '结束挑战',
    );
    if (confirmed && await _controller.endEarly()) _changed = true;
  }

  Future<void> _skipToday(HabitDetailViewData detail) async {
    final today = detail.dto.today;
    if (detail.lifecycle != HabitLifecycleStatusContract.active ||
        today == null ||
        today.status == HabitDailyStatusContract.skipped) {
      return;
    }
    final skipped = await _controller.setDay(
      date: today.date,
      status: HabitCheckInStatusContract.skipped,
    );
    if (skipped && mounted) {
      _changed = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('今天已跳过')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: '删除习惯？',
      body: '习惯会被软删除，提醒将停止。',
      action: '删除',
    );
    if (!confirmed) return;
    final deleted = await _controller.delete();
    if (deleted && mounted) {
      Navigator.of(context).pop(ContentDetailRouteOutcome.deleted);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  void _popWithResult() {
    if (_isPopping) return;
    _isPopping = true;
    Navigator.of(context).pop(
      _changed
          ? ContentDetailRouteOutcome.changed
          : ContentDetailRouteOutcome.unchanged,
    );
  }

  Future<void> _loadEarlier() async {
    if (_loadingEarlier) return;
    setState(() => _loadingEarlier = true);
    final response = await _controller.loadEarlierHistory(
      beforeDate: _earlier.isEmpty ? null : _earlier.last.date,
    );
    if (!mounted) return;
    if (response != null) {
      final existing = {
        ..._controller.detail!.history.map((item) => item.date),
        ..._earlier.map((item) => item.date),
      };
      _earlier.addAll(
        response.items.reversed.where((item) => existing.add(item.date)),
      );
    }
    setState(() => _loadingEarlier = false);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _popWithResult();
    },
    child: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        backgroundColor: HabitDesign.background(context),
        appBar: AppBar(
          backgroundColor: HabitDesign.background(context),
          leading: IconButton(
            tooltip: '返回',
            onPressed: _popWithResult,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('习惯详情'),
          actions: [
            if (_controller.detail != null)
              IconButton(
                tooltip: '删除习惯',
                onPressed: _controller.isMutating ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                color: HabitDesign.danger(context),
              ),
          ],
        ),
        body: _body(),
      ),
    ),
  );

  Widget _body() {
    if (_controller.phase == HabitDetailPhase.loading &&
        _controller.detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.phase == HabitDetailPhase.missing) {
      return const _DetailStatus(
        icon: Icons.event_busy_rounded,
        title: '该习惯不存在或已删除',
        body: '通知身份仍被保留，但目标已不可访问。',
      );
    }
    final detail = _controller.detail;
    if (detail == null) {
      return _DetailStatus(
        icon: Icons.sync_problem_rounded,
        title: '习惯加载失败',
        body: _controller.errorMessage ?? '请稍后重试',
        action: _controller.load,
      );
    }
    final history = [...detail.history, ..._earlier];
    final canLoadEarlier =
        detail.dto.hasEarlierHistory &&
        (history.isEmpty || history.last.date != detail.habit.startDate);
    final color = Theme.of(context).colorScheme.primary;
    return RefreshIndicator(
      onRefresh: () => _controller.load(preserve: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_controller.phase == HabitDetailPhase.refreshing ||
              _controller.isMutating)
            const LinearProgressIndicator(minHeight: 2),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: HabitDesign.surface(context),
              borderRadius: BorderRadius.circular(HabitDesign.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.habit.title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (detail.habit.description != null) ...[
                  const SizedBox(height: 8),
                  Text(detail.habit.description!),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Semantics(
                      label:
                          '挑战时间进度 ${(detail.dto.challengeTimeProgress * 100).round()}%',
                      child: SizedBox.square(
                        dimension: 72,
                        child: CircularProgressIndicator(
                          value: detail.dto.challengeTimeProgress,
                          strokeWidth: 8,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Text('连续 ${detail.dto.statistics.currentStreak} 天'),
                          Text('最长 ${detail.dto.statistics.longestStreak} 天'),
                          Text(
                            '完成率 ${(detail.dto.statistics.completionRateAll * 100).round()}%',
                          ),
                          Text('剩余 ${detail.dto.remainingDays} 天'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('每日提醒'),
              subtitle: Text(
                habitReminderSummary(
                  detail.dto.reminderSettings,
                  capability: _latestScheduleCapability,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Heatmap(history: history, onTap: _openDay),
          const SizedBox(height: 14),
          _History(history: history, onTap: _openDay),
          if (canLoadEarlier)
            TextButton(
              onPressed: _loadingEarlier ? null : _loadEarlier,
              child: Text(_loadingEarlier ? '加载中…' : '继续加载历史'),
            ),
          if (_controller.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                _controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 14),
          if (detail.lifecycle == HabitLifecycleStatusContract.active &&
              detail.dto.today != null)
            OutlinedButton.icon(
              onPressed:
                  _controller.isMutating ||
                      detail.dto.today!.status ==
                          HabitDailyStatusContract.skipped
                  ? null
                  : () => _skipToday(detail),
              icon: const Icon(Icons.skip_next_rounded),
              label: Text(
                detail.dto.today!.status == HabitDailyStatusContract.skipped
                    ? '今天已跳过'
                    : '跳过今天',
              ),
            ),
          if (!detail.isReadOnly)
            FilledButton.icon(
              onPressed: _controller.isMutating ? null : () => _edit(detail),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑习惯'),
            ),
          if (detail.lifecycle == HabitLifecycleStatusContract.active &&
              detail.dto.remainingDays > 1)
            OutlinedButton(
              onPressed: _controller.isMutating ? null : _end,
              child: const Text('提前结束'),
            ),
          if (detail.isReadOnly)
            FilledButton.tonal(
              onPressed: () => _restart(detail),
              child: const Text('再来一轮'),
            ),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.history, required this.onTap});
  final List<HabitDailyStatusResponseDto> history;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HabitDesign.surface(context),
      borderRadius: BorderRadius.circular(HabitDesign.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '挑战热力图',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final day in history.take(60))
              Semantics(
                button: true,
                label: '${formatHabitDate(day.date)}，${day.status.wireValue}',
                child: InkWell(
                  onTap: () => onTap(day.date),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _dayColor(context, day.status),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${DateTime.parse(day.date).day}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _History extends StatelessWidget {
  const _History({required this.history, required this.onTap});
  final List<HabitDailyStatusResponseDto> history;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: HabitDesign.surface(context),
      borderRadius: BorderRadius.circular(HabitDesign.radius),
    ),
    child: Column(
      children: [
        const ListTile(
          title: Text('历史记录', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        if (history.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('这里还没有历史记录')),
        for (final day in history)
          ListTile(
            title: Text(formatHabitDate(day.date)),
            subtitle: Text(day.status.wireValue),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onTap(day.date),
          ),
      ],
    ),
  );
}

Color _dayColor(BuildContext context, HabitDailyStatusContract status) =>
    switch (status) {
      HabitDailyStatusContract.done => Theme.of(context).colorScheme.primary,
      HabitDailyStatusContract.partial => Theme.of(
        context,
      ).colorScheme.primaryContainer,
      HabitDailyStatusContract.skipped => Theme.of(
        context,
      ).colorScheme.tertiaryContainer,
      HabitDailyStatusContract.missed => Theme.of(
        context,
      ).colorScheme.errorContainer,
      HabitDailyStatusContract.absent => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
      HabitDailyStatusContract.upcoming => Theme.of(
        context,
      ).colorScheme.surfaceContainer,
    };

class _DetailStatus extends StatelessWidget {
  const _DetailStatus({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: action, child: const Text('重试')),
          ],
        ],
      ),
    ),
  );
}

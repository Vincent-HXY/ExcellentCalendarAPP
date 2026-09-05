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
import '../widgets/habit_detail_sections.dart';
import '../widgets/habit_page_components.dart';
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
      body: '删除后，习惯将不再显示，相关提醒也会停止。',
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
        builder: (context) => HabitDialog(
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
      builder: (context, _) => HabitPageScaffold(
        leading: IconButton(
          tooltip: '返回',
          onPressed: _popWithResult,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: '习惯详情',
        actions: [
          if (_controller.detail != null)
            IconButton(
              tooltip: '删除习惯',
              onPressed: _controller.isMutating ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: HabitDesign.danger(context),
            ),
        ],
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
      return const HabitEmptyState(
        icon: Icons.event_busy_rounded,
        title: '该习惯不存在或已删除',
        message: '可以返回习惯列表，看看其他正在坚持的小目标。',
      );
    }
    final detail = _controller.detail;
    if (detail == null) {
      return HabitEmptyState(
        icon: Icons.sync_problem_rounded,
        title: '习惯加载失败',
        message: _controller.errorMessage ?? '请稍后重试',
        action: _controller.load,
      );
    }
    final history = [...detail.history, ..._earlier];
    final canLoadEarlier =
        detail.dto.hasEarlierHistory &&
        (history.isEmpty || history.last.date != detail.habit.startDate);
    return RefreshIndicator(
      onRefresh: () => _controller.load(preserve: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_controller.phase == HabitDetailPhase.refreshing ||
              _controller.isMutating)
            const LinearProgressIndicator(minHeight: 2),
          HabitDetailOverview(detail: detail),
          const SizedBox(height: 14),
          HabitSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: ListTile(
              leading: const HabitIconBadge(icon: Icons.notifications_outlined),
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
          HabitHeatmap(history: history, onTap: _openDay),
          const SizedBox(height: 14),
          HabitHistory(history: history, onTap: _openDay),
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
          if (!detail.isReadOnly) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _controller.isMutating ? null : () => _edit(detail),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑习惯'),
            ),
          ],
          if (detail.lifecycle == HabitLifecycleStatusContract.active &&
              detail.dto.remainingDays > 1) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _controller.isMutating ? null : _end,
              child: const Text('提前结束'),
            ),
          ],
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

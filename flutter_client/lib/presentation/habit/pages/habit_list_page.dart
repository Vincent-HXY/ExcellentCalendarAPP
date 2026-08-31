import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/habit/habit_form_controller.dart';
import '../../../application/habit/habit_list_controller.dart';
import '../../../application/habit/habit_models.dart';
import '../../../gateway_interfaces/habit_gateway.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../habit_design.dart';
import '../widgets/habit_card.dart';

class HabitListPage extends StatefulWidget {
  const HabitListPage({
    required this.gateway,
    required this.timezoneProvider,
    super.key,
  });
  final HabitGateway gateway;
  final String Function() timezoneProvider;

  @override
  State<HabitListPage> createState() => _HabitListPageState();
}

class _HabitListPageState extends State<HabitListPage>
    with WidgetsBindingObserver {
  late final HabitListController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = HabitListController(
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

  Future<void> _openExact(HabitCardViewData item) async {
    final text = TextEditingController(
      text: formatHundredths(item.completedCountHundredths ?? 0),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.title} · 精确数量'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(suffixText: item.unit, hintText: '0 可清除'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null || !mounted) return;
    try {
      final hundredths = parseHundredths(value)!;
      var clearConfirmed = false;
      if (hundredths == 0 && item.requiresClearConfirmation) {
        clearConfirmed = await _confirmClear(item);
        if (!clearConfirmed) return;
      }
      final succeeded = await _controller.setExactQuantity(
        item,
        hundredths,
        clearConfirmed: clearConfirmed,
      );
      if (succeeded) _showSuccess();
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入最多两位小数的有效数量')));
      }
    }
  }

  Future<void> _quickAction(HabitCardViewData item) async {
    var clearConfirmed = false;
    if (item.quickActionClears && item.requiresClearConfirmation) {
      clearConfirmed = await _confirmClear(item);
      if (!clearConfirmed) return;
    }
    final succeeded = await _controller.quickCheckIn(
      item,
      clearConfirmed: clearConfirmed,
    );
    if (succeeded) _showSuccess();
  }

  Future<void> _retryMutation() async {
    final succeeded = await _controller.retryLastMutation();
    if (succeeded) _showSuccess();
  }

  void _showSuccess() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('习惯记录已更新')));
  }

  Future<bool> _confirmClear(HabitCardViewData item) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('撤销 ${item.title} 的今日记录？'),
          content: Text(item.hasTodayNote ? '现有数量或备注会一起清除。' : '现有数量会被清除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认清除'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _openDetail(String id) async {
    await Navigator.of(context).pushNamed<void>('/habit/detail/$id');
    if (mounted) unawaited(_controller.load(preserve: true));
  }

  Future<void> _create() async {
    await Navigator.of(context).pushNamed<void>('/habit/create');
    if (mounted) unawaited(_controller.load(preserve: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HabitDesign.background(context),
      appBar: AppBar(
        backgroundColor: HabitDesign.background(context),
        title: const Text('习惯'),
        actions: [
          IconButton(
            tooltip: '新建习惯',
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_controller.phase == HabitListPhase.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.phase == HabitListPhase.error) {
      return _Status(
        title: '习惯加载失败',
        message: _controller.errorMessage ?? '请稍后重试',
        action: _controller.load,
      );
    }
    if (_controller.phase == HabitListPhase.empty) {
      return _Status(
        title: '从一个小目标开始',
        message: '建立固定期限的每日挑战，进度会保存在本机。',
        action: _create,
        actionLabel: '新建习惯',
      );
    }
    final progress = _controller.todayProgress;
    return RefreshIndicator(
      onRefresh: () => _controller.load(preserve: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_controller.phase == HabitListPhase.refreshing)
            const LinearProgressIndicator(minHeight: 2),
          if (_controller.errorMessage != null)
            MaterialBanner(
              content: Text(_controller.errorMessage!),
              actions: [
                if (_controller.canRetryMutation)
                  TextButton(
                    onPressed: _retryMutation,
                    child: const Text('重试'),
                  ),
                TextButton(
                  onPressed: _controller.clearError,
                  child: const Text('知道了'),
                ),
              ],
            ),
          _TodayProgress(
            done: progress?.done ?? 0,
            total: progress?.eligible ?? 0,
          ),
          _group('进行中', HabitLifecycleStatusContract.active),
          _group('即将开始', HabitLifecycleStatusContract.upcoming),
          _group('已结束', HabitLifecycleStatusContract.completed),
          _group('提前结束', HabitLifecycleStatusContract.endedEarly),
          if (_controller.hasMore || _controller.loadMoreErrorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  if (_controller.loadMoreErrorMessage != null) ...[
                    Text(
                      _controller.loadMoreErrorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: _controller.isLoadingMore
                        ? null
                        : () => unawaited(_controller.loadMore()),
                    icon: _controller.isLoadingMore
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: Text(
                      _controller.isLoadingMore
                          ? '加载中…'
                          : _controller.loadMoreErrorMessage != null
                          ? '重试加载更多'
                          : '继续加载更多习惯',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(String title, HabitLifecycleStatusContract lifecycle) {
    final items = _controller.group(lifecycle);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
          child: Text(
            '$title · ${items.length}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        for (final item in items) ...[
          HabitCard(
            key: ValueKey('habit-card-${item.id}'),
            item: item,
            mutating: _controller.mutatingIds.contains(item.id),
            succeeded: _controller.succeededIds.contains(item.id),
            onOpen: () => _openDetail(item.id),
            onQuickAction: item.canMutateToday
                ? () => _quickAction(item)
                : null,
            onExactQuantity: item.canMutateToday && item.isQuantitative
                ? () => _openExact(item)
                : null,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.done, required this.total});
  final int done;
  final int total;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '今日完成 $done / $total',
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(HabitDesign.radius),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph_rounded, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('今日完成', style: TextStyle(fontSize: 14)),
                Text(
                  '$done / $total',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({
    required this.title,
    required this.message,
    required this.action,
    this.actionLabel = '重试',
  });
  final String title;
  final String message;
  final VoidCallback action;
  final String actionLabel;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.track_changes_rounded, size: 52),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/ring/active_ring_session_controller.dart';

class ActiveRingSessionPage extends StatefulWidget {
  const ActiveRingSessionPage({required this.controller, super.key});

  final ActiveRingSessionController controller;

  @override
  State<ActiveRingSessionPage> createState() => _ActiveRingSessionPageState();
}

class _ActiveRingSessionPageState extends State<ActiveRingSessionPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102D35),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('活动响铃'),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, child) => _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    if (controller.status == ActiveRingLoadStatus.loading &&
        controller.snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!controller.hasActiveSession) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_off_outlined,
                color: Colors.white70,
                size: 52,
              ),
              const SizedBox(height: 16),
              Text(
                controller.errorMessage ?? '当前没有活动响铃',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: controller.status == ActiveRingLoadStatus.error
                    ? controller.refresh
                    : () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: Text(
                  controller.status == ActiveRingLoadStatus.error ? '重试' : '返回',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final items = controller.items;
    final multiple = items.length > 1;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              const Icon(
                Icons.alarm_rounded,
                color: Color(0xFF7DE3DB),
                size: 52,
              ),
              const SizedBox(height: 8),
              Text(
                multiple ? '${items.length} 个日程正在响铃' : '日程提醒',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (controller.errorMessage case final message?) ...[
                const SizedBox(height: 12),
                _LiveMessage(message: message, isError: true),
              ],
              if (controller.notice case final message?) ...[
                const SizedBox(height: 12),
                _LiveMessage(message: message),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _RingItemCard(
              view: items[index],
              disabled: controller.isActionRunning,
              onStop: () => controller.stopItem(items[index].item.deliveryId),
              onSnooze: () =>
                  controller.snoozeItem(items[index].item.deliveryId),
              onComplete: () =>
                  controller.completeItem(items[index].item.deliveryId),
            ),
          ),
        ),
        if (multiple)
          Container(
            color: const Color(0xFF0A2229),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: controller.isActionRunning
                        ? null
                        : controller.stopAll,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('关闭全部'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: controller.isActionRunning
                        ? null
                        : controller.snoozeAll,
                    icon: const Icon(Icons.snooze_rounded),
                    label: const Text('全部稍后 10 分钟'),
                  ),
                ),
              ],
            ),
          ),
        if (controller.isActionRunning)
          const LinearProgressIndicator(minHeight: 3, color: Color(0xFF7DE3DB)),
      ],
    );
  }
}

class _RingItemCard extends StatelessWidget {
  const _RingItemCard({
    required this.view,
    required this.disabled,
    required this.onStop,
    required this.onSnooze,
    required this.onComplete,
  });

  final ActiveRingItemView view;
  final bool disabled;
  final VoidCallback onStop;
  final VoidCallback onSnooze;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              view.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '原定 ${_formatLocalTime(view.item.plannedAt)}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            if (view.detailUnavailable)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '仍可关闭或稍后提醒；完成前可先重试页面',
                  style: TextStyle(color: Color(0xFFB45309)),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled ? null : onStop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('关闭'),
                ),
                OutlinedButton.icon(
                  onPressed: disabled ? null : onSnooze,
                  icon: const Icon(Icons.snooze_rounded),
                  label: const Text('稍后 10 分钟'),
                ),
                FilledButton.icon(
                  onPressed: disabled || view.detailUnavailable
                      ? null
                      : onComplete,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatLocalTime(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _LiveMessage extends StatelessWidget {
  const _LiveMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isError ? const Color(0xFF7F1D1D) : const Color(0xFF164E63),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

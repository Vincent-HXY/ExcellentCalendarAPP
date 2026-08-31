import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/habit/habit_day_controller.dart';
import '../../../application/habit/habit_form_controller.dart';
import '../../../application/habit/habit_models.dart';
import '../../../gateway_interfaces/habit_gateway.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../../../native_contract/habit/habit_response_dtos.dart';
import '../habit_design.dart';

class HabitDayPage extends StatefulWidget {
  const HabitDayPage({
    required this.habitId,
    required this.date,
    required this.gateway,
    required this.timezoneProvider,
    super.key,
  });
  final String habitId;
  final String date;
  final HabitGateway gateway;
  final String Function() timezoneProvider;

  @override
  State<HabitDayPage> createState() => _HabitDayPageState();
}

class _HabitDayPageState extends State<HabitDayPage> {
  late final HabitDayController _controller;
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  bool _inputsHydrated = false;

  @override
  void initState() {
    super.initState();
    _controller = HabitDayController(
      habitId: widget.habitId,
      date: widget.date,
      gateway: widget.gateway,
      timezoneProvider: widget.timezoneProvider,
    );
    _controller.addListener(_hydrateInputs);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    _controller.removeListener(_hydrateInputs);
    _controller.dispose();
    super.dispose();
  }

  void _hydrateInputs() {
    if (_inputsHydrated || _controller.phase != HabitDayPhase.ready) return;
    final checkIn = _controller.status?.checkIn;
    final quantity = checkIn?.completedCountHundredths;
    if (quantity != null) _quantity.text = formatHundredths(quantity);
    _note.text = checkIn?.note ?? '';
    _inputsHydrated = true;
  }

  Future<void> _set({required bool skipped}) async {
    final detail = _controller.detail;
    if (detail == null || !_controller.canMutate) return;
    final quantitative = detail.habit.isQuantitative;
    int? amount;
    if (!skipped && quantitative) {
      try {
        amount = parseHundredths(_quantity.text);
      } on FormatException {
        _message('请输入最多两位小数的有效数量');
        return;
      }
      if (amount == 0) {
        await _clear();
        return;
      }
    }
    await _controller.set(
      status: skipped
          ? HabitCheckInStatusContract.skipped
          : quantitative && amount! < detail.habit.targetCountHundredths!
          ? HabitCheckInStatusContract.partial
          : HabitCheckInStatusContract.done,
      completedCountHundredths: skipped ? null : amount,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
  }

  Future<void> _increment() async {
    final detail = _controller.detail;
    if (detail == null || !_controller.canMutate) return;
    final current = _controller.status?.checkIn?.completedCountHundredths ?? 0;
    if (current > 9007199254740891) {
      _message('数量已达到可保存上限');
      return;
    }
    _quantity.text = formatHundredths(current + 100);
    await _set(skipped: false);
  }

  Future<void> _clear() async {
    final status = _controller.status;
    if (status?.checkIn != null &&
        (status!.checkIn!.completedCountHundredths != null ||
            status.checkIn!.note != null)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('撤销这天的记录？'),
          content: const Text('数量和备注会一起清除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final cleared = await _controller.clear();
    if (cleared) {
      _quantity.clear();
      _note.clear();
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: HabitDesign.background(context),
    appBar: AppBar(
      backgroundColor: HabitDesign.background(context),
      title: Text(formatHabitDate(widget.date)),
    ),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final detail = _controller.detail;
        if (_controller.phase == HabitDayPhase.loading || detail == null) {
          if (_controller.phase == HabitDayPhase.error ||
              _controller.phase == HabitDayPhase.missing) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _controller.errorMessage ?? '该习惯不存在或已删除',
                      textAlign: TextAlign.center,
                    ),
                    if (_controller.phase == HabitDayPhase.error) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _controller.load,
                        child: const Text('重试'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final status = _controller.status;
        final readOnly = !_controller.canMutate;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DaySummary(status: status),
            const SizedBox(height: 14),
            if (readOnly)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(_controller.readOnlyMessage),
                ),
              )
            else ...[
              if (detail.habit.isQuantitative)
                TextField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '完成数量',
                    suffixText: detail.habit.unit,
                  ),
                ),
              if (detail.habit.isQuantitative) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _controller.isMutating ? null : _increment,
                  icon: const Icon(Icons.add_rounded),
                  label: Text('+1 ${detail.habit.unit ?? ''}'.trim()),
                ),
              ],
              TextField(
                controller: _note,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注（可选）'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _controller.isMutating
                    ? null
                    : () => _set(skipped: false),
                icon: const Icon(Icons.check_rounded),
                label: Text(detail.habit.isQuantitative ? '保存数量' : '标记完成'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _controller.isMutating
                    ? null
                    : () => _set(skipped: true),
                child: const Text('跳过这一天'),
              ),
              TextButton(
                onPressed: _controller.isMutating ? null : _clear,
                child: const Text('清除记录'),
              ),
            ],
            if (_controller.errorMessage != null)
              Text(
                _controller.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        );
      },
    ),
  );
}

class _DaySummary extends StatelessWidget {
  const _DaySummary({required this.status});
  final HabitDailyStatusResponseDto? status;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(
            status?.status == HabitDailyStatusContract.done
                ? Icons.check_circle
                : Icons.calendar_today,
            size: 34,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status == null ? '暂无当日投影' : '状态：${status!.status.wireValue}',
            ),
          ),
        ],
      ),
    ),
  );
}

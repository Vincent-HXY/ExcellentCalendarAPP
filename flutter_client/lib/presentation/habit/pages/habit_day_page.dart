import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/habit/habit_day_controller.dart';
import '../../../application/habit/habit_form_controller.dart';
import '../../../application/habit/habit_models.dart';
import '../../../gateway_interfaces/habit_gateway.dart';
import '../../../native_contract/habit/habit_contract_enums.dart';
import '../../../native_contract/habit/habit_response_dtos.dart';
import '../habit_design.dart';
import '../widgets/habit_page_components.dart';

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
        builder: (context) => HabitDialog(
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
  Widget build(BuildContext context) => HabitPageScaffold(
    title: formatHabitDate(widget.date),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final detail = _controller.detail;
        if (_controller.phase == HabitDayPhase.loading || detail == null) {
          if (_controller.phase == HabitDayPhase.error ||
              _controller.phase == HabitDayPhase.missing) {
            return HabitEmptyState(
              icon: Icons.event_busy_outlined,
              title: _controller.phase == HabitDayPhase.missing
                  ? '该习惯不存在或已删除'
                  : '记录加载失败',
              message: _controller.errorMessage ?? '可以返回习惯列表，查看其他记录。',
              action: _controller.phase == HabitDayPhase.error
                  ? _controller.load
                  : null,
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final status = _controller.status;
        final readOnly = !_controller.canMutate;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _DaySummary(title: detail.habit.title, status: status),
            const SizedBox(height: 14),
            if (readOnly)
              HabitSectionCard(
                child: Text(
                  _controller.readOnlyMessage,
                  style: TextStyle(
                    color: HabitDesign.muted(context),
                    height: 1.6,
                  ),
                ),
              )
            else ...[
              HabitSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HabitSectionHeading(
                      title: '记录这一天',
                      icon: Icons.edit_note_rounded,
                    ),
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
                      OutlinedButton(
                        onPressed: _controller.isMutating ? null : _increment,
                        child: Text('+1 ${detail.habit.unit ?? ''}'.trim()),
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextField(
                      controller: _note,
                      maxLength: 500,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '备注（可选）',
                        hintText: '记下今天的一点感受…',
                      ),
                    ),
                  ],
                ),
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
  const _DaySummary({required this.title, required this.status});
  final String title;
  final HabitDailyStatusResponseDto? status;
  @override
  Widget build(BuildContext context) => HabitSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            HabitIconBadge(
              icon: status == null
                  ? Icons.calendar_today_outlined
                  : habitDayStatusIcon(status!.status),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        HabitLabel(
          text: status == null
              ? '这一天暂无记录'
              : habitDayStatusLabel(status!.status),
        ),
        if (status?.checkIn?.completedCountHundredths case final amount?) ...[
          const SizedBox(height: 12),
          Text(
            '已记录 ${formatHundredths(amount)} ${status!.checkIn!.unitSnapshot ?? ''}',
            style: TextStyle(color: HabitDesign.muted(context), fontSize: 13),
          ),
        ],
        if (status?.checkIn?.note case final note?) ...[
          const SizedBox(height: 10),
          Text(
            '当日备注：$note',
            style: TextStyle(color: HabitDesign.muted(context), height: 1.6),
          ),
        ],
      ],
    ),
  );
}

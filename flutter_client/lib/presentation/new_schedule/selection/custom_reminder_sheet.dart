import 'package:flutter/material.dart';

import '../date_time_picker/picker_wheel_column.dart';
import '../new_schedule_design_tokens.dart';
import 'floating_selection_sheet.dart';

Future<int?> showCustomReminderSheet({
  required BuildContext context,
  int? initialAdvanceMinutes,
}) {
  return showFloatingSelectionSheet<int>(
    context: context,
    builder: (context) {
      return _CustomReminderSheet(
        initialAdvanceMinutes: initialAdvanceMinutes ?? 15,
      );
    },
  );
}

class _CustomReminderSheet extends StatefulWidget {
  const _CustomReminderSheet({required this.initialAdvanceMinutes});

  final int initialAdvanceMinutes;

  @override
  State<_CustomReminderSheet> createState() => _CustomReminderSheetState();
}

class _CustomReminderSheetState extends State<_CustomReminderSheet> {
  late int _days;
  late int _hours;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    final normalized = widget.initialAdvanceMinutes.clamp(1, 365 * 1440);
    _days = normalized ~/ 1440;
    _hours = (normalized % 1440) ~/ 60;
    _minutes = normalized % 60;
  }

  int get _advanceMinutes => _days * 1440 + _hours * 60 + _minutes;

  void _confirm() {
    if (_advanceMinutes <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少选择 1 分钟')));
      return;
    }
    Navigator.of(context).pop(_advanceMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingSelectionSheet(
      title: '自定义提醒时间',
      subtitle: '设置日程开始前多久提醒',
      maxHeightFactor: 0.78,
      onCancel: () => Navigator.of(context).pop(null),
      onConfirm: _confirm,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_days 天 $_hours 小时 $_minutes 分钟前',
              style: NewScheduleTextStyles.rowValue.copyWith(
                color: NewScheduleColors.body,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: MagnifyingNumberWheel(
                    itemCount: 366,
                    selectedIndex: _days,
                    unit: '天',
                    onChanged: (value) => setState(() => _days = value),
                  ),
                ),
                Expanded(
                  child: MagnifyingNumberWheel(
                    itemCount: 24,
                    selectedIndex: _hours,
                    unit: '小时',
                    onChanged: (value) => setState(() => _hours = value),
                  ),
                ),
                Expanded(
                  child: MagnifyingNumberWheel(
                    itemCount: 60,
                    selectedIndex: _minutes,
                    unit: '分钟',
                    onChanged: (value) => setState(() => _minutes = value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MagnifyingNumberWheel extends StatelessWidget {
  const MagnifyingNumberWheel({
    required this.itemCount,
    required this.selectedIndex,
    required this.unit,
    required this.onChanged,
    super.key,
  });

  final int itemCount;
  final int selectedIndex;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return PickerWheelColumn(
      itemCount: itemCount,
      selectedIndex: selectedIndex,
      width: 96,
      labelBuilder: (index) => '$index $unit',
      onSelectedItemChanged: onChanged,
    );
  }
}

import 'package:flutter/material.dart';

import '../new_schedule_draft.dart';
import 'custom_reminder_sheet.dart';
import 'floating_selection_sheet.dart';

class ReminderSelectionResult {
  const ReminderSelectionResult({
    required this.presets,
    required this.customAdvanceMinutes,
  });

  final Set<ReminderPreset> presets;
  final int? customAdvanceMinutes;
}

Future<ReminderSelectionResult?> showReminderSelectionSheet({
  required BuildContext context,
  required Set<ReminderPreset> initialPresets,
  required int? initialCustomAdvanceMinutes,
  required VoidCallback onRemainingTenPercentUnsupported,
}) {
  return showFloatingSelectionSheet<ReminderSelectionResult>(
    context: context,
    builder: (context) {
      return _ReminderSelectionSheet(
        initialPresets: initialPresets,
        initialCustomAdvanceMinutes: initialCustomAdvanceMinutes,
        onRemainingTenPercentUnsupported: onRemainingTenPercentUnsupported,
      );
    },
  );
}

class _ReminderSelectionSheet extends StatefulWidget {
  const _ReminderSelectionSheet({
    required this.initialPresets,
    required this.initialCustomAdvanceMinutes,
    required this.onRemainingTenPercentUnsupported,
  });

  final Set<ReminderPreset> initialPresets;
  final int? initialCustomAdvanceMinutes;
  final VoidCallback onRemainingTenPercentUnsupported;

  @override
  State<_ReminderSelectionSheet> createState() =>
      _ReminderSelectionSheetState();
}

class _ReminderSelectionSheetState extends State<_ReminderSelectionSheet> {
  late Set<ReminderPreset> _draftSelections;
  late int? _customAdvanceMinutes;

  @override
  void initState() {
    super.initState();
    _draftSelections = {...widget.initialPresets};
    _customAdvanceMinutes = widget.initialCustomAdvanceMinutes;
  }

  Future<void> _toggle(ReminderPreset preset) async {
    if (preset == ReminderPreset.remainingTenPercent) {
      widget.onRemainingTenPercentUnsupported();
      return;
    }
    if (preset == ReminderPreset.custom) {
      final value = await showCustomReminderSheet(
        context: context,
        initialAdvanceMinutes: _customAdvanceMinutes,
      );
      if (value == null || !mounted) {
        return;
      }
      setState(() {
        _customAdvanceMinutes = value;
        _draftSelections.add(ReminderPreset.custom);
      });
      return;
    }

    setState(() {
      if (_draftSelections.contains(preset)) {
        _draftSelections.remove(preset);
      } else {
        _draftSelections.add(preset);
      }
    });
  }

  String _titleFor(ReminderPreset preset) {
    if (preset == ReminderPreset.custom && _customAdvanceMinutes != null) {
      return '自定义：${formatReminderAdvanceMinutes(_customAdvanceMinutes!)}';
    }
    return preset.label;
  }

  @override
  Widget build(BuildContext context) {
    final options = ReminderPreset.values;
    return FloatingSelectionSheet(
      title: '默认提醒时间',
      subtitle: '可设置多个提醒',
      onCancel: () => Navigator.of(context).pop(null),
      onConfirm: () {
        Navigator.of(context).pop(
          ReminderSelectionResult(
            presets: {..._draftSelections},
            customAdvanceMinutes: _customAdvanceMinutes,
          ),
        );
      },
      content: ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, index) {
          final option = options[index];
          return SelectionOptionTile(
            title: _titleFor(option),
            showDivider: index != options.length - 1,
            indicator: SelectionCheckboxIndicator(
              selected: _draftSelections.contains(option),
            ),
            onTap: () => _toggle(option),
          );
        },
      ),
    );
  }
}

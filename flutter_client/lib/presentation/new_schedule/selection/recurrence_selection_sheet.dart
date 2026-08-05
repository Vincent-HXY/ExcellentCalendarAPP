import 'package:flutter/material.dart';

import '../new_schedule_draft.dart';
import 'floating_selection_sheet.dart';

Future<RecurrencePreset?> showRecurrenceSelectionSheet({
  required BuildContext context,
  required RecurrencePreset initialValue,
  required ValueChanged<RecurrencePreset> onUnsupported,
}) {
  return showFloatingSelectionSheet<RecurrencePreset>(
    context: context,
    builder: (sheetContext) {
      return _RecurrenceSelectionSheet(
        initialValue: initialValue,
        onUnsupported: onUnsupported,
      );
    },
  );
}

class _RecurrenceSelectionSheet extends StatefulWidget {
  const _RecurrenceSelectionSheet({
    required this.initialValue,
    required this.onUnsupported,
  });

  final RecurrencePreset initialValue;
  final ValueChanged<RecurrencePreset> onUnsupported;

  @override
  State<_RecurrenceSelectionSheet> createState() =>
      _RecurrenceSelectionSheetState();
}

class _RecurrenceSelectionSheetState extends State<_RecurrenceSelectionSheet> {
  late RecurrencePreset _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final options = RecurrencePreset.values;
    return FloatingSelectionSheet(
      title: '重复频率',
      subtitle: '请选择一种重复方式',
      onCancel: () => Navigator.of(context).pop(null),
      onConfirm: () => Navigator.of(context).pop(_draft),
      content: ListView.builder(
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, index) {
          final option = options[index];
          return SelectionOptionTile(
            title: option.label,
            showDivider: index != options.length - 1,
            indicator: SelectionRadioIndicator(selected: option == _draft),
            onTap: () {
              if (option == RecurrencePreset.yearly ||
                  option == RecurrencePreset.custom) {
                widget.onUnsupported(option);
                return;
              }
              setState(() {
                _draft = option;
              });
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app_switch.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    required this.isRingingReminderEnabled,
    required this.reminderSummary,
    required this.onReminderTap,
    required this.onRingingReminderChanged,
    super.key,
  });

  final bool isRingingReminderEnabled;
  final String reminderSummary;
  final VoidCallback onReminderTap;
  final ValueChanged<bool> onRingingReminderChanged;

  @override
  Widget build(BuildContext context) {
    return FormSectionCard(
      child: Column(
        children: [
          FormRowItem(
            label: '提醒',
            value: reminderSummary,
            showDivider: true,
            onTap: onReminderTap,
          ),
          FormRowItem(
            label: '响铃提醒',
            showChevron: false,
            trailing: AppSwitch(
              value: isRingingReminderEnabled,
              semanticLabel: '响铃提醒',
              onChanged: onRingingReminderChanged,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'custom_checkbox.dart';

class TaskListItem extends StatelessWidget {
  const TaskListItem({
    required this.task,
    required this.showDivider,
    super.key,
  });

  final InboxTaskViewData task;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: InboxSizes.rowHeight,
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: InboxColors.divider, width: 0.75),
              )
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: InboxSpacing.rowHorizontal,
        ),
        child: Row(
          children: [
            CustomCheckbox(
              isChecked: task.isCompleted,
              isImportant: task.importance.isImportant,
            ),
            const SizedBox(width: InboxSpacing.checkboxGap),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: InboxTextStyles.taskTitle.copyWith(
                  color: task.isCompleted
                      ? InboxColors.mutedText
                      : InboxTextStyles.taskTitle.color,
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (task.dueDateLabel != null) ...[
              const SizedBox(width: InboxSpacing.dateGap),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: InboxSizes.dateMaxWidth,
                ),
                child: Text(
                  task.dueDateLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: InboxTextStyles.dueDate,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

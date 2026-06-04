// 文件作用：Inbox 列表里的单条任务行，展示复选框、标题和可选到期日期标签。
// 设计边界：这里只呈现完成态，不在点击时修改真实任务状态。
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

  // 数据块作用：单行任务要展示的标题、完成态、重要性和日期标签。
  final InboxTaskViewData task;
  // 数据块作用：是否绘制底部分割线，通常最后一行不显示。
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制单条任务行，并根据完成态调整标题颜色和删除线。
    // 关键视觉：固定行高保证列表密度稳定，避免标题/日期变化撑开布局。
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

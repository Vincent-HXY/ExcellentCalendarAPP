import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'task_list_item.dart';

class TaskListCard extends StatelessWidget {
  const TaskListCard({required this.tasks, super.key});

  final List<InboxTaskViewData> tasks;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(InboxSizes.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(
          vertical: InboxSpacing.cardVerticalPadding,
        ),
        itemCount: tasks.length,
        itemExtent: InboxSizes.rowHeight,
        itemBuilder: (context, index) {
          return TaskListItem(
            task: tasks[index],
            showDivider: index != tasks.length - 1,
          );
        },
      ),
    );
  }
}

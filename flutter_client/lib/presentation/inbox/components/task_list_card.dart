import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'task_list_item.dart';

class TaskListCard extends StatefulWidget {
  const TaskListCard({required this.tasks, super.key});

  final List<InboxTaskViewData> tasks;

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  bool _isIncompleteExpanded = true;
  bool _isUpcomingExpanded = true;
  bool _isCompletedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final activeTasks = widget.tasks
        .where((task) => !task.isCompleted && task.dueDateLabel == null)
        .toList(growable: false);
    final dueSoonTasks = widget.tasks
        .where((task) => !task.isCompleted)
        .where((task) => task.dueDateLabel != null)
        .toList(growable: false);
    final completedTasks = widget.tasks
        .where((task) => task.isCompleted)
        .toList(growable: false);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TaskGroupCard(
          title: '未完成',
          tasks: activeTasks,
          isExpanded: _isIncompleteExpanded,
          onHeaderTap: () {
            setState(() {
              _isIncompleteExpanded = !_isIncompleteExpanded;
            });
          },
        ),
        const SizedBox(height: InboxSpacing.groupSpacing),
        TaskGroupCard(
          title: '即将到期',
          tasks: dueSoonTasks,
          isExpanded: _isUpcomingExpanded,
          onHeaderTap: () {
            setState(() {
              _isUpcomingExpanded = !_isUpcomingExpanded;
            });
          },
        ),
        const SizedBox(height: InboxSpacing.groupSpacing),
        TaskGroupCard(
          title: '已完成',
          tasks: completedTasks,
          isExpanded: _isCompletedExpanded,
          onHeaderTap: () {
            setState(() {
              _isCompletedExpanded = !_isCompletedExpanded;
            });
          },
        ),
      ],
    );
  }
}

class TaskGroupCard extends StatelessWidget {
  const TaskGroupCard({
    required this.title,
    required this.tasks,
    required this.isExpanded,
    required this.onHeaderTap,
    super.key,
  });

  final String title;
  final List<InboxTaskViewData> tasks;
  final bool isExpanded;
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InboxColors.surface,
        borderRadius: BorderRadius.circular(InboxSizes.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onHeaderTap,
            child: SizedBox(
              height: InboxSizes.groupHeaderHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: InboxSpacing.groupHeaderHorizontal,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: InboxTextStyles.groupTitle,
                      ),
                    ),
                    Text('${tasks.length}', style: InboxTextStyles.groupCount),
                    const SizedBox(width: InboxSpacing.groupHeaderGap),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: InboxColors.mutedText,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(
                      bottom: InboxSpacing.cardVerticalPadding,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < tasks.length; index++)
                          TaskListItem(
                            task: tasks[index],
                            showDivider: index != tasks.length - 1,
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

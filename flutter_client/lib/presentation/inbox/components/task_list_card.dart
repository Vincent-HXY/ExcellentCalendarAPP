import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'task_list_item.dart';

typedef TaskCompleteCallback = Future<bool> Function(InboxTaskViewData task);

class TaskListCard extends StatefulWidget {
  const TaskListCard({
    required this.tasks,
    this.completedTasks = const [],
    this.completedCountLabel,
    this.completingIds = const {},
    this.isLoadingCompleted = false,
    this.completedError,
    this.onTaskComplete,
    this.onTaskRemovalFinished,
    this.onCompletedExpandedChanged,
    super.key,
  });

  final List<InboxTaskViewData> tasks;
  final List<InboxTaskViewData> completedTasks;
  final String? completedCountLabel;
  final Set<String> completingIds;
  final bool isLoadingCompleted;
  final String? completedError;
  final TaskCompleteCallback? onTaskComplete;
  final ValueChanged<String>? onTaskRemovalFinished;
  final ValueChanged<bool>? onCompletedExpandedChanged;

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
        .where((task) => !task.isCompleted && task.dueDateLabel != null)
        .toList(growable: false);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        TaskGroupCard(
          title: '未完成',
          tasks: activeTasks,
          isExpanded: _isIncompleteExpanded,
          emptyMessage: '暂无未完成日程',
          completingIds: widget.completingIds,
          onTaskComplete: widget.onTaskComplete,
          onTaskRemovalFinished: widget.onTaskRemovalFinished,
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
          emptyMessage: '暂无即将到期日程',
          completingIds: widget.completingIds,
          onTaskComplete: widget.onTaskComplete,
          onTaskRemovalFinished: widget.onTaskRemovalFinished,
          onHeaderTap: () {
            setState(() {
              _isUpcomingExpanded = !_isUpcomingExpanded;
            });
          },
        ),
        const SizedBox(height: InboxSpacing.groupSpacing),
        TaskGroupCard(
          title: '已完成',
          tasks: widget.completedTasks,
          countLabel: widget.completedCountLabel,
          isExpanded: _isCompletedExpanded,
          isLoading: widget.isLoadingCompleted,
          errorText: widget.completedError,
          emptyMessage: '暂无已完成日程',
          onHeaderTap: () {
            final nextValue = !_isCompletedExpanded;
            setState(() {
              _isCompletedExpanded = nextValue;
            });
            widget.onCompletedExpandedChanged?.call(nextValue);
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
    this.completingIds = const {},
    this.isLoading = false,
    this.errorText,
    this.countLabel,
    this.emptyMessage = '暂无日程',
    this.onTaskComplete,
    this.onTaskRemovalFinished,
    super.key,
  });

  final String title;
  final List<InboxTaskViewData> tasks;
  final bool isExpanded;
  final VoidCallback onHeaderTap;
  final Set<String> completingIds;
  final bool isLoading;
  final String? errorText;
  final String? countLabel;
  final String emptyMessage;
  final TaskCompleteCallback? onTaskComplete;
  final ValueChanged<String>? onTaskRemovalFinished;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final sectionExpandDuration = disableAnimations
        ? Duration.zero
        : AppMotion.sectionExpand;
    final sectionCollapseDuration = disableAnimations
        ? Duration.zero
        : AppMotion.sectionCollapse;
    final arrowDuration = disableAnimations
        ? Duration.zero
        : AppMotion.arrowRotation;

    return Container(
      decoration: BoxDecoration(
        color: InboxColors.surface,
        borderRadius: BorderRadius.circular(InboxSizes.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
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
                    Text(
                      countLabel ?? '${tasks.length}',
                      style: InboxTextStyles.groupCount,
                    ),
                    const SizedBox(width: InboxSpacing.groupHeaderGap),
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: arrowDuration,
                      curve: AppMotion.standard,
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
            duration: sectionExpandDuration,
            reverseDuration: sectionCollapseDuration,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: ClipRect(
              child: isExpanded
                  ? Padding(
                      padding: const EdgeInsets.only(
                        bottom: InboxSpacing.cardVerticalPadding,
                      ),
                      child: _buildBody(),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading && tasks.isEmpty) {
      return const SizedBox(
        height: InboxSizes.rowHeight,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: InboxColors.accent,
            ),
          ),
        ),
      );
    }
    if (errorText != null && tasks.isEmpty) {
      return _GroupMessage(message: errorText!);
    }
    if (tasks.isEmpty) {
      return _GroupMessage(message: emptyMessage);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < tasks.length; index++)
          TaskListItem(
            key: ValueKey(tasks[index].id),
            task: tasks[index],
            showDivider: index != tasks.length - 1,
            isCompleting: completingIds.contains(tasks[index].id),
            onComplete: onTaskComplete == null
                ? null
                : () => onTaskComplete!(tasks[index]),
            onRemovalFinished: onTaskRemovalFinished == null
                ? null
                : () => onTaskRemovalFinished!(tasks[index].id),
          ),
      ],
    );
  }
}

class _GroupMessage extends StatelessWidget {
  const _GroupMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: InboxSizes.rowHeight,
      child: Center(
        child: Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: InboxTextStyles.groupCount,
        ),
      ),
    );
  }
}

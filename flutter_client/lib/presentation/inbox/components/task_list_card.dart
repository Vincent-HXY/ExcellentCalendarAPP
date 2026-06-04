// 文件作用：Inbox 首页任务分组卡片，负责未完成/即将到期/已完成三段折叠展示。
// 设计边界：当前分组是 UI 临时逻辑，真实“今日任务”分组应由 Application/Query 产出。
import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'task_list_item.dart';

class TaskListCard extends StatefulWidget {
  const TaskListCard({required this.tasks, super.key});

  // 数据块作用：父页面传入的任务视图数据，当前在组件内临时分成三组。
  final List<InboxTaskViewData> tasks;

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  // 数据块作用：控制“未完成”分组是否展开。
  bool _isIncompleteExpanded = true;
  // 数据块作用：控制“即将到期”分组是否展开。
  bool _isUpcomingExpanded = true;
  // 数据块作用：控制“已完成”分组是否展开，默认收起以突出未完成任务。
  bool _isCompletedExpanded = false;

  @override
  Widget build(BuildContext context) {
    // 函数作用：把任务按当前 UI 规则分组，并渲染三个可折叠分组卡片。
    // 关键判断：dueDateLabel != null 被临时视为“即将到期”。
    // 后续应改用真实 startAt/remindAt 与当前日期计算出的分组字段。
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

  // 数据块作用：分组标题，例如未完成、即将到期、已完成。
  final String title;
  // 数据块作用：该分组内需要展示的任务列表。
  final List<InboxTaskViewData> tasks;
  // 数据块作用：控制当前分组内容是否展开。
  final bool isExpanded;
  // 数据块作用：点击分组标题时触发的折叠/展开回调。
  final VoidCallback onHeaderTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制一个任务分组卡片，包括标题栏、数量、箭头和任务行列表。
    // 关键布局：圆角卡片承载一个分组；折叠状态由父组件维护，便于未来迁移到 state_management。
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

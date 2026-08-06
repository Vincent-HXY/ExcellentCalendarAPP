// 文件作用：Inbox 首页专用的视图数据模型，屏蔽底层 Event/Habit/Reminder 的复杂字段。
// 设计边界：这是 Presentation ViewData，不应承载核心领域规则。
import '../../event_detail/models/event_detail_ui_state.dart';

enum TaskImportance {
  unimportantNotUrgent('unimportant_noturgent'),
  importantNotUrgent('important_noturgent'),
  unimportantUrgent('unimportant_urgent'),
  importantUrgent('important_urgent');

  const TaskImportance(this.wireValue);

  // 数据块作用：底层重要性枚举的字符串值，后续对接存储/接口时保持字段一致。
  final String wireValue;

  // 关键判断：当前复选框高亮只需要知道是否“重要”，不区分紧急程度。
  bool get isImportant =>
      this == TaskImportance.importantNotUrgent ||
      this == TaskImportance.importantUrgent;
}

class InboxTaskViewData {
  const InboxTaskViewData({
    required this.id,
    required this.title,
    required this.importance,
    required this.isCompleted,
    this.hasRecurrence = false,
    this.dueDateLabel,
    this.detailState,
  });

  // 数据块作用：任务唯一标识，后续用于完成、编辑、删除等交互回传。
  final String id;
  // 数据块作用：任务主标题，首页任务行的主要展示文本。
  final String title;
  // 数据块作用：面向 UI 的日期标签，例如 Today 或 Jun 4；不等同于真实 DateTime。
  final String? dueDateLabel;
  // 数据块作用：任务重要性，用于四象限语义和首页视觉强调。
  final TaskImportance importance;
  // 数据块作用：任务是否完成，决定所在分组和标题样式。
  final bool isCompleted;
  final bool hasRecurrence;
  final EventDetailUiState? detailState;
}

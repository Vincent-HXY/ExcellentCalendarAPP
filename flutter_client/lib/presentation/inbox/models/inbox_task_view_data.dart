enum TaskImportance {
  unimportantNotUrgent('unimportant_noturgent'),
  importantNotUrgent('important_noturgent'),
  unimportantUrgent('unimportant_urgent'),
  importantUrgent('important_urgent');

  const TaskImportance(this.wireValue);

  final String wireValue;

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
    this.dueDateLabel,
  });

  final String id;
  final String title;
  final String? dueDateLabel;
  final TaskImportance importance;
  final bool isCompleted;
}

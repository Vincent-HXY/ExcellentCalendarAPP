// 文件作用：定义新建日程提交入口和当前阶段的 EventDraft 数据契约。
// 设计边界：EventDraft 字段对齐 docs/DATA_MODEL.md 的 Event；Reminder 仍应独立建模。
abstract interface class ScheduleCreateUseCase {
  Future<void> createSchedule(EventDraft draft);
}

// 关键数据：当前只表达 Event 本体，不包含提醒方式/提醒时间；
// 按数据模型，提醒应在后续流程中生成一条或多条 Reminder。
class EventDraft {
  const EventDraft({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.createdAt,
    required this.updatedAt,
    required this.hasRecurrence,
    required this.source,
    this.content,
    this.recurrenceId,
    this.categoryId,
    this.importance,
    this.location,
    this.timezone,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? content;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool hasRecurrence;
  final String? recurrenceId;
  final String? categoryId;
  final String? importance;
  final String? location;
  final String? timezone;
  final String source;
  final DateTime? deletedAt;

  Map<String, Object?> toJson() {
    // 关键数据：时间暂用 ISO 8601 序列化；文档允许 ISO 字符串或 UTC 时间戳。
    // 如果第一版采用 JSON Storage 的 Unix milliseconds，需要在网关/仓储层统一转换。
    return {
      'id': id,
      'title': title,
      'content': content,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt.toIso8601String(),
      'isAllDay': isAllDay,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'hasRecurrence': hasRecurrence,
      'recurrenceId': recurrenceId,
      'categoryId': categoryId,
      'importance': importance,
      'location': location,
      'timezone': timezone,
      'source': source,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}

import '../recurrence/recurrence_rule_dto.dart';
import '../reminder/reminder_draft_request_dto.dart';

class CreateEventRequestDto {
  const CreateEventRequestDto({
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.source,
    this.content,
    this.categoryId,
    this.importance,
    this.location,
    this.timezone,
    this.recurrence,
    this.reminders = const [],
  });

  final String title;
  final String? content;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final String? categoryId;
  final String? importance;
  final String? location;
  final String? timezone;
  final String source;
  final RecurrenceRuleDto? recurrence;
  final List<ReminderDraftRequestDto> reminders;

  Map<String, dynamic> toJson() {
    _validateSource(source);
    if (importance != null) {
      _validateImportance(importance!);
    }
    return {
      'title': title,
      'content': content,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'is_all_day': isAllDay,
      'category_id': categoryId,
      'importance': importance,
      'location': location,
      'timezone': timezone,
      'source': source,
      'recurrence': recurrence?.toJson(),
      'reminders': reminders.map((reminder) => reminder.toJson()).toList(),
    };
  }

  static void _validateImportance(String value) {
    const allowed = {
      'unimportant_noturgent',
      'important_noturgent',
      'unimportant_urgent',
      'important_urgent',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown Importance: $value');
    }
  }

  static void _validateSource(String value) {
    const allowed = {'manual', 'ai_extraction', 'sync', 'import', 'wechat'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown CreateEvent source: $value');
    }
  }
}

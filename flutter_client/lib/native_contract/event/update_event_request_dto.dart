import '../recurrence/recurrence_rule_dto.dart';
import '../reminder/reminder_draft_request_dto.dart';
import '../shared/contract_field.dart';

class UpdateEventRequestDto {
  const UpdateEventRequestDto({
    required this.id,
    this.title,
    this.content = const ContractField<String>.absent(),
    this.startAt,
    this.endAt,
    this.isAllDay,
    this.categoryId = const ContractField<String>.absent(),
    this.importance = const ContractField<String>.absent(),
    this.location = const ContractField<String>.absent(),
    this.timezone = const ContractField<String>.absent(),
    this.source,
    this.recurrence = const ContractField<RecurrenceRuleDto>.absent(),
    this.reminders,
  });

  final String id;
  final String? title;
  final ContractField<String> content;
  final DateTime? startAt;
  final DateTime? endAt;
  final bool? isAllDay;
  final ContractField<String> categoryId;
  final ContractField<String> importance;
  final ContractField<String> location;
  final ContractField<String> timezone;
  final String? source;
  final ContractField<RecurrenceRuleDto> recurrence;
  final List<ReminderDraftRequestDto>? reminders;

  Map<String, dynamic> toJson() {
    if (id.trim().isEmpty) {
      throw const FormatException('UpdateEventRequest.id must be non-empty.');
    }
    if (title != null && title!.isEmpty) {
      throw const FormatException(
        'UpdateEventRequest.title must be non-empty when provided.',
      );
    }
    final importanceValue = importance.value;
    if (importance.isPresent && importanceValue != null) {
      _validateImportance(importanceValue);
    }
    if (source != null) _validateSource(source!);

    final json = <String, dynamic>{'id': id};
    if (title != null) json['title'] = title;
    if (content.isPresent) json['content'] = content.value;
    if (startAt != null) json['start_at'] = startAt!.toUtc().toIso8601String();
    if (endAt != null) json['end_at'] = endAt!.toUtc().toIso8601String();
    if (isAllDay != null) json['is_all_day'] = isAllDay;
    if (categoryId.isPresent) json['category_id'] = categoryId.value;
    if (importance.isPresent) json['importance'] = importance.value;
    if (location.isPresent) json['location'] = location.value;
    if (timezone.isPresent) json['timezone'] = timezone.value;
    if (source != null) json['source'] = source;
    if (recurrence.isPresent) {
      json['recurrence'] = recurrence.value?.toJson();
    }
    if (reminders != null) {
      json['reminders'] = reminders!
          .map((reminder) => reminder.toJson())
          .toList(growable: false);
    }
    return json;
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
      throw FormatException('Unknown UpdateEvent source: $value');
    }
  }
}

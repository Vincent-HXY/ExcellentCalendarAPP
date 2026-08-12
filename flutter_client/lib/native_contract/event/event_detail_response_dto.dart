import '../category/category_response_dto.dart';
import '../recurrence/recurrence_response_dto.dart';
import '../reminder/reminder_response_dto.dart';
import '../shared/contract_value.dart';
import 'event_response_dto.dart';

class EventDetailResponseDto {
  const EventDetailResponseDto({
    required this.event,
    required this.recurrence,
    required this.reminders,
    required this.category,
  });

  final EventResponseDto event;
  final RecurrenceResponseDto? recurrence;
  final List<ReminderResponseDto> reminders;
  final CategoryResponseDto? category;

  factory EventDetailResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'event',
      'recurrence',
      'reminders',
      'category',
    }, 'EventDetailResponse');
    final rawEvent = json['event'];
    final rawRecurrence = json['recurrence'];
    final rawReminders = json['reminders'];
    final rawCategory = json['category'];
    if (rawEvent is! Map<String, dynamic> ||
        (rawRecurrence != null && rawRecurrence is! Map<String, dynamic>) ||
        rawReminders is! List ||
        rawReminders.any((item) => item is! Map<String, dynamic>) ||
        (rawCategory != null && rawCategory is! Map<String, dynamic>)) {
      throw const FormatException('EventDetailResponse shape is invalid.');
    }
    final event = EventResponseDto.fromJson(rawEvent);
    final recurrence = rawRecurrence == null
        ? null
        : RecurrenceResponseDto.fromJson(rawRecurrence);
    if (event.hasRecurrence != (recurrence != null) ||
        (recurrence != null &&
            (event.recurrenceId != recurrence.recurrenceId ||
                event.recurrenceRevision != recurrence.revision))) {
      throw const FormatException(
        'EventDetailResponse recurrence projection is inconsistent.',
      );
    }
    final category = rawCategory == null
        ? null
        : CategoryResponseDto.fromJson(rawCategory);
    if (category != null &&
        (event.categoryId == null ||
            category.id != event.categoryId ||
            category.deletedAt != null)) {
      throw const FormatException(
        'EventDetailResponse category projection is inconsistent.',
      );
    }
    return EventDetailResponseDto(
      event: event,
      recurrence: recurrence,
      reminders: List<ReminderResponseDto>.unmodifiable(
        rawReminders.cast<Map<String, dynamic>>().map(
          ReminderResponseDto.fromJson,
        ),
      ),
      category: category,
    );
  }
}

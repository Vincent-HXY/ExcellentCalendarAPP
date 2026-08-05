import '../recurrence/recurrence_rule_dto.dart';
import '../reminder/reminder_draft_request_dto.dart';
import '../shared/contract_value.dart';

class CreateEventRequestDto {
  const CreateEventRequestDto({
    required this.title,
    required this.isAllDay,
    required this.timezone,
    required this.source,
    this.startAt,
    this.endAt,
    this.startDate,
    this.endDate,
    this.content,
    this.categoryId,
    this.importance,
    this.location,
    this.recurrence,
    this.reminders = const [],
  });

  const CreateEventRequestDto.timed({
    required this.title,
    required DateTime this.startAt,
    required DateTime this.endAt,
    required this.timezone,
    required this.source,
    this.content,
    this.categoryId,
    this.importance,
    this.location,
    this.recurrence,
    this.reminders = const [],
  }) : isAllDay = false,
       startDate = null,
       endDate = null;

  const CreateEventRequestDto.allDay({
    required this.title,
    required String this.startDate,
    required String this.endDate,
    required this.timezone,
    required this.source,
    this.content,
    this.categoryId,
    this.importance,
    this.location,
    this.recurrence,
    this.reminders = const [],
  }) : isAllDay = true,
       startAt = null,
       endAt = null;

  static const _importanceValues = {
    'unimportant_noturgent',
    'important_noturgent',
    'unimportant_urgent',
    'important_urgent',
  };
  static const _sourceValues = {
    'manual',
    'ai_extraction',
    'sync',
    'import',
    'wechat',
  };

  final String title;
  final String? content;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final bool isAllDay;
  final String? categoryId;
  final String? importance;
  final String? location;
  final String timezone;
  final String source;
  final EventRecurrenceRuleInputDto? recurrence;
  final List<EventReminderDraftRequestDto> reminders;

  Map<String, dynamic> toJson() {
    if (title.isEmpty) {
      throw const FormatException(
        'CreateEventRequest.title must be non-empty.',
      );
    }
    if (timezone.isEmpty) {
      throw const FormatException(
        'CreateEventRequest.timezone must be non-empty.',
      );
    }
    if (importance != null) {
      ContractValue.validateEnum(importance!, _importanceValues, 'Importance');
    }
    ContractValue.validateEnum(source, _sourceValues, 'CreateEvent source');

    String? startAtValue;
    String? endAtValue;
    String? startDateValue;
    String? endDateValue;
    if (isAllDay) {
      if (startAt != null ||
          endAt != null ||
          startDate == null ||
          endDate == null) {
        throw const FormatException(
          'CreateEventRequest all-day time fields are invalid.',
        );
      }
      ContractValue.validateLocalDate(
        startDate!,
        field: 'CreateEventRequest.start_date',
      );
      ContractValue.validateLocalDate(
        endDate!,
        field: 'CreateEventRequest.end_date',
      );
      if (!ContractValue.localDateAsDateTime(
        startDate!,
        field: 'CreateEventRequest.start_date',
      ).isBefore(
        ContractValue.localDateAsDateTime(
          endDate!,
          field: 'CreateEventRequest.end_date',
        ),
      )) {
        throw const FormatException(
          'CreateEventRequest all-day range must be positive.',
        );
      }
      startDateValue = startDate;
      endDateValue = endDate;
    } else {
      if (startAt == null ||
          endAt == null ||
          startDate != null ||
          endDate != null) {
        throw const FormatException(
          'CreateEventRequest timed fields are invalid.',
        );
      }
      if (!startAt!.isUtc || !endAt!.isUtc) {
        throw const FormatException(
          'CreateEventRequest timed instants must already be UTC.',
        );
      }
      if (!startAt!.isBefore(endAt!)) {
        throw const FormatException(
          'CreateEventRequest timed range must be positive.',
        );
      }
      startAtValue = ContractValue.formatUtcSecond(
        startAt!,
        field: 'CreateEventRequest.start_at',
      );
      endAtValue = ContractValue.formatUtcSecond(
        endAt!,
        field: 'CreateEventRequest.end_at',
      );
    }

    if (isAllDay && recurrence != null && reminders.isNotEmpty) {
      throw const FormatException(
        'Recurring all-day Events do not support reminders in Contract v2.',
      );
    }
    final isRecurring = recurrence != null;
    return {
      'title': title,
      'content': content,
      'start_at': startAtValue,
      'end_at': endAtValue,
      'start_date': startDateValue,
      'end_date': endDateValue,
      'is_all_day': isAllDay,
      'category_id': categoryId,
      'importance': importance,
      'location': location,
      'timezone': timezone,
      'source': source,
      'recurrence': recurrence?.toJson(),
      'reminders': reminders
          .map((reminder) => reminder.toEventJson(recurring: isRecurring))
          .toList(growable: false),
    };
  }
}

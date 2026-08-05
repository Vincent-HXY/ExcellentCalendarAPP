import '../recurrence/recurrence_rule_dto.dart';
import '../reminder/reminder_draft_request_dto.dart';
import '../shared/contract_field.dart';
import '../shared/contract_value.dart';

class UpdateEventRequestDto {
  const UpdateEventRequestDto({
    required this.id,
    this.expectedRecurrenceRevision,
    this.title,
    this.content = const ContractField<String>.absent(),
    this.startAt,
    this.endAt,
    this.startDate,
    this.endDate,
    this.isAllDay,
    this.categoryId = const ContractField<String>.absent(),
    this.importance = const ContractField<String>.absent(),
    this.location = const ContractField<String>.absent(),
    this.timezone,
    this.source,
    this.recurrence = const ContractField<EventRecurrenceRuleInputDto>.absent(),
    this.reminders,
  });

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

  final String id;
  final int? expectedRecurrenceRevision;
  final String? title;
  final ContractField<String> content;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final bool? isAllDay;
  final ContractField<String> categoryId;
  final ContractField<String> importance;
  final ContractField<String> location;
  final String? timezone;
  final String? source;
  final ContractField<EventRecurrenceRuleInputDto> recurrence;
  final List<EventReminderDraftRequestDto>? reminders;

  Map<String, dynamic> toJson() {
    if (id.trim().isEmpty) {
      throw const FormatException('UpdateEventRequest.id must be non-empty.');
    }
    if (expectedRecurrenceRevision != null && expectedRecurrenceRevision! < 1) {
      throw const FormatException(
        'UpdateEventRequest.expected_recurrence_revision must be positive.',
      );
    }
    if (title != null && title!.isEmpty) {
      throw const FormatException(
        'UpdateEventRequest.title must be non-empty when provided.',
      );
    }
    final importanceValue = importance.value;
    if (importance.isPresent && importanceValue != null) {
      ContractValue.validateEnum(
        importanceValue,
        _importanceValues,
        'Importance',
      );
    }
    if (source != null) {
      ContractValue.validateEnum(source!, _sourceValues, 'UpdateEvent source');
    }
    if (recurrence.isPresent && recurrence.value == null) {
      throw const FormatException(
        'UpdateEventRequest.recurrence cannot be null in Contract v2.',
      );
    }

    final json = <String, dynamic>{'id': id};
    if (expectedRecurrenceRevision != null) {
      json['expected_recurrence_revision'] = expectedRecurrenceRevision;
    }
    if (title != null) json['title'] = title;
    if (content.isPresent) json['content'] = content.value;
    if (categoryId.isPresent) json['category_id'] = categoryId.value;
    if (importance.isPresent) json['importance'] = importance.value;
    if (location.isPresent) json['location'] = location.value;
    if (source != null) json['source'] = source;

    final hasTimeMutation =
        startAt != null ||
        endAt != null ||
        startDate != null ||
        endDate != null ||
        isAllDay != null ||
        timezone != null;
    if (hasTimeMutation) {
      if (isAllDay == null || timezone == null || timezone!.isEmpty) {
        throw const FormatException(
          'UpdateEventRequest time changes require the complete atomic group.',
        );
      }
      if (isAllDay!) {
        if (startAt != null ||
            endAt != null ||
            startDate == null ||
            endDate == null) {
          throw const FormatException(
            'UpdateEventRequest all-day time fields are invalid.',
          );
        }
        ContractValue.validateLocalDate(
          startDate!,
          field: 'UpdateEventRequest.start_date',
        );
        ContractValue.validateLocalDate(
          endDate!,
          field: 'UpdateEventRequest.end_date',
        );
        if (!ContractValue.localDateAsDateTime(
          startDate!,
          field: 'UpdateEventRequest.start_date',
        ).isBefore(
          ContractValue.localDateAsDateTime(
            endDate!,
            field: 'UpdateEventRequest.end_date',
          ),
        )) {
          throw const FormatException(
            'UpdateEventRequest all-day range must be positive.',
          );
        }
        json.addAll({
          'start_at': null,
          'end_at': null,
          'start_date': startDate,
          'end_date': endDate,
          'is_all_day': true,
          'timezone': timezone,
        });
      } else {
        if (startAt == null ||
            endAt == null ||
            startDate != null ||
            endDate != null ||
            !startAt!.isBefore(endAt!)) {
          throw const FormatException(
            'UpdateEventRequest timed fields are invalid.',
          );
        }
        if (!startAt!.isUtc || !endAt!.isUtc) {
          throw const FormatException(
            'UpdateEventRequest timed instants must already be UTC.',
          );
        }
        json.addAll({
          'start_at': ContractValue.formatUtcSecond(
            startAt!,
            field: 'UpdateEventRequest.start_at',
          ),
          'end_at': ContractValue.formatUtcSecond(
            endAt!,
            field: 'UpdateEventRequest.end_at',
          ),
          'start_date': null,
          'end_date': null,
          'is_all_day': false,
          'timezone': timezone,
        });
      }
    }

    if (recurrence.isPresent) {
      json['recurrence'] = recurrence.value!.toJson();
    }
    if (reminders != null) {
      final isRecurringUpdate =
          recurrence.isPresent || expectedRecurrenceRevision != null;
      if (isRecurringUpdate && isAllDay == true && reminders!.isNotEmpty) {
        throw const FormatException(
          'Recurring all-day Events do not support reminders in Contract v2.',
        );
      }
      json['reminders'] = reminders!
          .map((reminder) => reminder.toEventJson(recurring: isRecurringUpdate))
          .toList(growable: false);
    }
    return json;
  }
}

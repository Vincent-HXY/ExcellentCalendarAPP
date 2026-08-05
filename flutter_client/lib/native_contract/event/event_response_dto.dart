import '../shared/contract_value.dart';

class EventResponseDto {
  const EventResponseDto({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.startDate,
    required this.endDate,
    required this.isAllDay,
    required this.hasRecurrence,
    required this.status,
    required this.recurrenceId,
    required this.recurrenceRevision,
    required this.timezone,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.content,
    this.completedAt,
    this.categoryId,
    this.importance,
    this.location,
    this.deletedAt,
  });

  static const _keys = {
    'id',
    'title',
    'content',
    'start_at',
    'end_at',
    'start_date',
    'end_date',
    'is_all_day',
    'has_recurrence',
    'status',
    'completed_at',
    'recurrence_id',
    'recurrence_revision',
    'category_id',
    'importance',
    'location',
    'timezone',
    'source',
    'created_at',
    'updated_at',
    'deleted_at',
  };
  static const _statuses = {'active', 'completed', 'cancelled', 'archived'};
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
  final String title;
  final String? content;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final bool isAllDay;
  final bool hasRecurrence;
  final String status;
  final DateTime? completedAt;
  final String? recurrenceId;
  final int? recurrenceRevision;
  final String? categoryId;
  final String? importance;
  final String? location;
  final String timezone;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  DateTime get displayStartAt =>
      startAt ??
      ContractValue.localDateAsDateTime(
        startDate!,
        field: 'EventResponse.start_date',
      );

  DateTime get displayEndAt =>
      endAt ??
      ContractValue.localDateAsDateTime(
        endDate!,
        field: 'EventResponse.end_date',
      );

  factory EventResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'EventResponse');
    final isAllDay = ContractValue.boolean(json, 'is_all_day', 'EventResponse');
    final startAt = ContractValue.optionalUtcDateTime(
      json,
      'start_at',
      'EventResponse',
      wholeSecond: true,
    );
    final endAt = ContractValue.optionalUtcDateTime(
      json,
      'end_at',
      'EventResponse',
      wholeSecond: true,
    );
    final startDate = ContractValue.optionalLocalDate(
      json,
      'start_date',
      'EventResponse',
    );
    final endDate = ContractValue.optionalLocalDate(
      json,
      'end_date',
      'EventResponse',
    );
    if (isAllDay) {
      if (startAt != null ||
          endAt != null ||
          startDate == null ||
          endDate == null ||
          !ContractValue.localDateAsDateTime(
            startDate,
            field: 'EventResponse.start_date',
          ).isBefore(
            ContractValue.localDateAsDateTime(
              endDate,
              field: 'EventResponse.end_date',
            ),
          )) {
        throw const FormatException('EventResponse all-day shape is invalid.');
      }
    } else if (startAt == null ||
        endAt == null ||
        startDate != null ||
        endDate != null ||
        !startAt.isBefore(endAt)) {
      throw const FormatException('EventResponse timed shape is invalid.');
    }

    final hasRecurrence = ContractValue.boolean(
      json,
      'has_recurrence',
      'EventResponse',
    );
    final recurrenceId = ContractValue.optionalString(
      json,
      'recurrence_id',
      'EventResponse',
    );
    final recurrenceRevision = ContractValue.optionalInteger(
      json,
      'recurrence_revision',
      'EventResponse',
      minimum: 1,
    );
    if (hasRecurrence != (recurrenceId != null && recurrenceRevision != null)) {
      throw const FormatException(
        'EventResponse recurrence identity is inconsistent.',
      );
    }

    final status = ContractValue.nonEmptyString(
      json,
      'status',
      'EventResponse',
    );
    ContractValue.validateEnum(status, _statuses, 'EventStatus');
    final importance = ContractValue.optionalString(
      json,
      'importance',
      'EventResponse',
    );
    if (importance != null) {
      ContractValue.validateEnum(importance, _importanceValues, 'Importance');
    }
    final source = ContractValue.nonEmptyString(
      json,
      'source',
      'EventResponse',
    );
    ContractValue.validateEnum(source, _sourceValues, 'DataSource');

    return EventResponseDto(
      id: ContractValue.nonEmptyString(json, 'id', 'EventResponse'),
      title: ContractValue.nonEmptyString(json, 'title', 'EventResponse'),
      content: ContractValue.optionalString(json, 'content', 'EventResponse'),
      startAt: startAt,
      endAt: endAt,
      startDate: startDate,
      endDate: endDate,
      isAllDay: isAllDay,
      hasRecurrence: hasRecurrence,
      status: status,
      completedAt: ContractValue.optionalUtcDateTime(
        json,
        'completed_at',
        'EventResponse',
      ),
      recurrenceId: recurrenceId,
      recurrenceRevision: recurrenceRevision,
      categoryId: ContractValue.optionalString(
        json,
        'category_id',
        'EventResponse',
      ),
      importance: importance,
      location: ContractValue.optionalString(json, 'location', 'EventResponse'),
      timezone: ContractValue.nonEmptyString(json, 'timezone', 'EventResponse'),
      source: source,
      createdAt: ContractValue.utcDateTime(json, 'created_at', 'EventResponse'),
      updatedAt: ContractValue.utcDateTime(json, 'updated_at', 'EventResponse'),
      deletedAt: ContractValue.optionalUtcDateTime(
        json,
        'deleted_at',
        'EventResponse',
      ),
    );
  }
}

import '../shared/contract_value.dart';

class EventOccurrenceStateResponseDto {
  const EventOccurrenceStateResponseDto({
    required this.eventId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required this.occurrenceStartAt,
    required this.occurrenceStartDate,
    required this.status,
    required this.stateChangedAt,
    required this.reopenedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  static const _keys = {
    'event_id',
    'recurrence_revision',
    'occurrence_key',
    'occurrence_start_at',
    'occurrence_start_date',
    'status',
    'state_changed_at',
    'reopened_at',
    'created_at',
    'updated_at',
  };
  static const _statuses = {'scheduled', 'completed', 'skipped', 'cancelled'};

  final String eventId;
  final int recurrenceRevision;
  final String occurrenceKey;
  final DateTime? occurrenceStartAt;
  final String? occurrenceStartDate;
  final String status;
  final DateTime stateChangedAt;
  final DateTime? reopenedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory EventOccurrenceStateResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'EventOccurrenceStateResponse');
    final occurrenceStartAt = ContractValue.optionalUtcDateTime(
      json,
      'occurrence_start_at',
      'EventOccurrenceStateResponse',
      wholeSecond: true,
    );
    final occurrenceStartDate = ContractValue.optionalLocalDate(
      json,
      'occurrence_start_date',
      'EventOccurrenceStateResponse',
    );
    if ((occurrenceStartAt == null) == (occurrenceStartDate == null)) {
      throw const FormatException(
        'EventOccurrenceStateResponse must contain exactly one start shape.',
      );
    }
    final status = ContractValue.nonEmptyString(
      json,
      'status',
      'EventOccurrenceStateResponse',
    );
    ContractValue.validateEnum(status, _statuses, 'EventOccurrenceStatus');
    return EventOccurrenceStateResponseDto(
      eventId: ContractValue.nonEmptyString(
        json,
        'event_id',
        'EventOccurrenceStateResponse',
      ),
      recurrenceRevision: ContractValue.integer(
        json,
        'recurrence_revision',
        'EventOccurrenceStateResponse',
        minimum: 1,
      ),
      occurrenceKey: ContractValue.nonEmptyString(
        json,
        'occurrence_key',
        'EventOccurrenceStateResponse',
      ),
      occurrenceStartAt: occurrenceStartAt,
      occurrenceStartDate: occurrenceStartDate,
      status: status,
      stateChangedAt: ContractValue.utcDateTime(
        json,
        'state_changed_at',
        'EventOccurrenceStateResponse',
      ),
      reopenedAt: ContractValue.optionalUtcDateTime(
        json,
        'reopened_at',
        'EventOccurrenceStateResponse',
      ),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'EventOccurrenceStateResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'EventOccurrenceStateResponse',
      ),
    );
  }
}

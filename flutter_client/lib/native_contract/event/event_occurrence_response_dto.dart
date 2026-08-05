import '../shared/contract_value.dart';
import 'event_occurrence_state_response_dto.dart';

class EventOccurrenceResponseDto {
  const EventOccurrenceResponseDto({
    required this.eventId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required this.occurrenceStartAt,
    required this.occurrenceEndAt,
    required this.occurrenceStartDate,
    required this.occurrenceEndDate,
    required this.timezone,
    required this.state,
  });

  static const _keys = {
    'event_id',
    'recurrence_revision',
    'occurrence_key',
    'occurrence_start_at',
    'occurrence_end_at',
    'occurrence_start_date',
    'occurrence_end_date',
    'timezone',
    'state',
  };

  final String eventId;
  final int recurrenceRevision;
  final String occurrenceKey;
  final DateTime? occurrenceStartAt;
  final DateTime? occurrenceEndAt;
  final String? occurrenceStartDate;
  final String? occurrenceEndDate;
  final String timezone;
  final EventOccurrenceStateResponseDto? state;

  factory EventOccurrenceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'EventOccurrenceResponse');
    final startAt = ContractValue.optionalUtcDateTime(
      json,
      'occurrence_start_at',
      'EventOccurrenceResponse',
      wholeSecond: true,
    );
    final endAt = ContractValue.optionalUtcDateTime(
      json,
      'occurrence_end_at',
      'EventOccurrenceResponse',
      wholeSecond: true,
    );
    final startDate = ContractValue.optionalLocalDate(
      json,
      'occurrence_start_date',
      'EventOccurrenceResponse',
    );
    final endDate = ContractValue.optionalLocalDate(
      json,
      'occurrence_end_date',
      'EventOccurrenceResponse',
    );
    final timed = startAt != null && endAt != null;
    final allDay = startDate != null && endDate != null;
    if (timed == allDay ||
        (timed && !startAt.isBefore(endAt)) ||
        (allDay &&
            !ContractValue.localDateAsDateTime(
              startDate,
              field: 'EventOccurrenceResponse.occurrence_start_date',
            ).isBefore(
              ContractValue.localDateAsDateTime(
                endDate,
                field: 'EventOccurrenceResponse.occurrence_end_date',
              ),
            ))) {
      throw const FormatException('EventOccurrenceResponse time is invalid.');
    }
    final rawState = json['state'];
    if (rawState != null && rawState is! Map<String, dynamic>) {
      throw const FormatException(
        'EventOccurrenceResponse.state must be object or null.',
      );
    }
    final eventId = ContractValue.nonEmptyString(
      json,
      'event_id',
      'EventOccurrenceResponse',
    );
    final recurrenceRevision = ContractValue.integer(
      json,
      'recurrence_revision',
      'EventOccurrenceResponse',
      minimum: 1,
    );
    final occurrenceKey = ContractValue.nonEmptyString(
      json,
      'occurrence_key',
      'EventOccurrenceResponse',
    );
    final state = rawState == null
        ? null
        : EventOccurrenceStateResponseDto.fromJson(rawState);
    final stateStartMatches =
        state == null ||
        (startAt != null &&
            state.occurrenceStartAt != null &&
            startAt.isAtSameMomentAs(state.occurrenceStartAt!)) ||
        (startDate != null && state.occurrenceStartDate == startDate);
    if (state != null &&
        (state.eventId != eventId ||
            state.recurrenceRevision != recurrenceRevision ||
            state.occurrenceKey != occurrenceKey ||
            !stateStartMatches)) {
      throw const FormatException(
        'EventOccurrenceResponse.state identity is inconsistent.',
      );
    }
    return EventOccurrenceResponseDto(
      eventId: eventId,
      recurrenceRevision: recurrenceRevision,
      occurrenceKey: occurrenceKey,
      occurrenceStartAt: startAt,
      occurrenceEndAt: endAt,
      occurrenceStartDate: startDate,
      occurrenceEndDate: endDate,
      timezone: ContractValue.nonEmptyString(
        json,
        'timezone',
        'EventOccurrenceResponse',
      ),
      state: state,
    );
  }
}

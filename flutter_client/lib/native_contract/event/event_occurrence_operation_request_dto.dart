import '../shared/contract_value.dart';

class EventOccurrenceOperationRequestDto {
  const EventOccurrenceOperationRequestDto({
    required this.eventId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required this.occurrenceStartAt,
    required this.occurrenceStartDate,
  });

  const EventOccurrenceOperationRequestDto.timed({
    required this.eventId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required DateTime this.occurrenceStartAt,
  }) : occurrenceStartDate = null;

  const EventOccurrenceOperationRequestDto.allDay({
    required this.eventId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required String this.occurrenceStartDate,
  }) : occurrenceStartAt = null;

  final String eventId;
  final int recurrenceRevision;
  final String occurrenceKey;
  final DateTime? occurrenceStartAt;
  final String? occurrenceStartDate;

  Map<String, dynamic> toJson() {
    if (eventId.trim().isEmpty ||
        occurrenceKey.trim().isEmpty ||
        recurrenceRevision < 1 ||
        ((occurrenceStartAt == null) == (occurrenceStartDate == null))) {
      throw const FormatException(
        'EventOccurrenceOperationRequest identity is invalid.',
      );
    }
    if (occurrenceStartDate != null) {
      ContractValue.validateLocalDate(
        occurrenceStartDate!,
        field: 'EventOccurrenceOperationRequest.occurrence_start_date',
      );
    }
    return {
      'event_id': eventId,
      'recurrence_revision': recurrenceRevision,
      'occurrence_key': occurrenceKey,
      'occurrence_start_at': occurrenceStartAt == null
          ? null
          : ContractValue.formatUtcSecond(
              occurrenceStartAt!,
              field: 'EventOccurrenceOperationRequest.occurrence_start_at',
            ),
      'occurrence_start_date': occurrenceStartDate,
    };
  }
}

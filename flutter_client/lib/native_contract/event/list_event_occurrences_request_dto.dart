import '../shared/contract_value.dart';

class ListEventOccurrencesRequestDto {
  const ListEventOccurrencesRequestDto({
    required this.eventId,
    required this.recurrenceRevision,
    required this.isAllDay,
    required this.rangeStartAt,
    required this.rangeEndAt,
    required this.rangeStartDate,
    required this.rangeEndDate,
    this.cursor,
    this.limit = 100,
  });

  const ListEventOccurrencesRequestDto.timed({
    required this.eventId,
    required this.recurrenceRevision,
    required DateTime this.rangeStartAt,
    required DateTime this.rangeEndAt,
    this.cursor,
    this.limit = 100,
  }) : isAllDay = false,
       rangeStartDate = null,
       rangeEndDate = null;

  const ListEventOccurrencesRequestDto.allDay({
    required this.eventId,
    required this.recurrenceRevision,
    required String this.rangeStartDate,
    required String this.rangeEndDate,
    this.cursor,
    this.limit = 100,
  }) : isAllDay = true,
       rangeStartAt = null,
       rangeEndAt = null;

  final String eventId;
  final int recurrenceRevision;
  final bool isAllDay;
  final DateTime? rangeStartAt;
  final DateTime? rangeEndAt;
  final String? rangeStartDate;
  final String? rangeEndDate;
  final String? cursor;
  final int limit;

  Map<String, dynamic> toJson() {
    if (eventId.trim().isEmpty || recurrenceRevision < 1) {
      throw const FormatException(
        'ListEventOccurrencesRequest identity is invalid.',
      );
    }
    if (limit < 1 || limit > 200) {
      throw const FormatException(
        'ListEventOccurrencesRequest.limit must be between 1 and 200.',
      );
    }
    String? rangeStartAtValue;
    String? rangeEndAtValue;
    if (isAllDay) {
      if (rangeStartAt != null ||
          rangeEndAt != null ||
          rangeStartDate == null ||
          rangeEndDate == null) {
        throw const FormatException(
          'ListEventOccurrencesRequest all-day range is invalid.',
        );
      }
      ContractValue.validateLocalDate(
        rangeStartDate!,
        field: 'ListEventOccurrencesRequest.range_start_date',
      );
      ContractValue.validateLocalDate(
        rangeEndDate!,
        field: 'ListEventOccurrencesRequest.range_end_date',
      );
      if (!ContractValue.localDateAsDateTime(
        rangeStartDate!,
        field: 'ListEventOccurrencesRequest.range_start_date',
      ).isBefore(
        ContractValue.localDateAsDateTime(
          rangeEndDate!,
          field: 'ListEventOccurrencesRequest.range_end_date',
        ),
      )) {
        throw const FormatException(
          'ListEventOccurrencesRequest all-day range must be positive.',
        );
      }
    } else {
      if (rangeStartAt == null ||
          rangeEndAt == null ||
          rangeStartDate != null ||
          rangeEndDate != null ||
          !rangeStartAt!.isBefore(rangeEndAt!)) {
        throw const FormatException(
          'ListEventOccurrencesRequest timed range is invalid.',
        );
      }
      rangeStartAtValue = ContractValue.formatUtcDateTime(
        rangeStartAt!,
        field: 'ListEventOccurrencesRequest.range_start_at',
      );
      rangeEndAtValue = ContractValue.formatUtcDateTime(
        rangeEndAt!,
        field: 'ListEventOccurrencesRequest.range_end_at',
      );
    }
    return {
      'event_id': eventId,
      'recurrence_revision': recurrenceRevision,
      'is_all_day': isAllDay,
      'range_start_at': rangeStartAtValue,
      'range_end_at': rangeEndAtValue,
      'range_start_date': rangeStartDate,
      'range_end_date': rangeEndDate,
      'cursor': cursor,
      'limit': limit,
    };
  }
}

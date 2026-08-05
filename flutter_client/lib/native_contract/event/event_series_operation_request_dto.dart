class EventSeriesOperationRequestDto {
  const EventSeriesOperationRequestDto({
    required this.eventId,
    required this.recurrenceRevision,
  });

  final String eventId;
  final int recurrenceRevision;

  Map<String, dynamic> toJson() {
    if (eventId.trim().isEmpty || recurrenceRevision < 1) {
      throw const FormatException(
        'EventSeriesOperationRequest identity is invalid.',
      );
    }
    return {'event_id': eventId, 'recurrence_revision': recurrenceRevision};
  }
}

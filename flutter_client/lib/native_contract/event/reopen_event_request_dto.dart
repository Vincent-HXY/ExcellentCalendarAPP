class ReopenEventRequestDto {
  const ReopenEventRequestDto({required this.eventId, this.occurrenceStartAt});

  final String eventId;
  final DateTime? occurrenceStartAt;

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'occurrence_start_at': occurrenceStartAt?.toUtc().toIso8601String(),
    };
  }
}

class ReopenEventRequestDto {
  const ReopenEventRequestDto({required this.eventId});

  final String eventId;

  Map<String, dynamic> toJson() {
    if (eventId.trim().isEmpty) {
      throw const FormatException(
        'ReopenEventRequest.event_id must be non-empty.',
      );
    }
    return {'event_id': eventId};
  }
}

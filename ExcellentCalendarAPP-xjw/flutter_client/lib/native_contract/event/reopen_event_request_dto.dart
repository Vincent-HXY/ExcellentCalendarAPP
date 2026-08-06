class ReopenEventRequestDto {
  const ReopenEventRequestDto({required this.eventId});

  final String eventId;

  Map<String, dynamic> toJson() {
    return {'event_id': eventId};
  }
}

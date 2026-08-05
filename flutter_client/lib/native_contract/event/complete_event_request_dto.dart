class CompleteEventRequestDto {
  const CompleteEventRequestDto({
    required this.eventId,
    required this.source,
    this.note,
  });

  final String eventId;
  final String source;
  final String? note;

  Map<String, dynamic> toJson() {
    if (eventId.trim().isEmpty) {
      throw const FormatException(
        'CompleteEventRequest.event_id must be non-empty.',
      );
    }
    _validateSource(source);
    return {'event_id': eventId, 'source': source, 'note': note};
  }

  static void _validateSource(String value) {
    const allowed = {
      'manual',
      'auto',
      'ai_extraction',
      'sync',
      'import',
      'wechat',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown CompleteEvent source: $value');
    }
  }
}

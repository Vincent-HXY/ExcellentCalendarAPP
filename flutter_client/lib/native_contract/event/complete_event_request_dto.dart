class CompleteEventRequestDto {
  const CompleteEventRequestDto({
    required this.eventId,
    required this.completedAt,
    required this.source,
    this.note,
  });

  final String eventId;
  final DateTime completedAt;
  final String source;
  final String? note;

  Map<String, dynamic> toJson() {
    _validateSource(source);
    return {
      'event_id': eventId,
      'completed_at': completedAt.toUtc().toIso8601String(),
      'source': source,
      'note': note,
    };
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

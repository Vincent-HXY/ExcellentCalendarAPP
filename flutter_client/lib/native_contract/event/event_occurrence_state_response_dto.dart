import '../shared/contract_json_object.dart';

class EventOccurrenceStateResponseDto {
  const EventOccurrenceStateResponseDto({
    required this.id,
    required this.eventId,
    required this.occurrenceStartAt,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String eventId;
  final DateTime occurrenceStartAt;
  final String status;
  final DateTime? completedAt;
  final String? note;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory EventOccurrenceStateResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'id',
      'event_id',
      'occurrence_start_at',
      'status',
      'completed_at',
      'note',
      'source',
      'created_at',
      'updated_at',
      'deleted_at',
    }, 'EventOccurrenceStateResponse');
    ContractJsonObject.requireKeys(json, {
      'id',
      'event_id',
      'occurrence_start_at',
      'status',
      'source',
      'created_at',
      'updated_at',
    }, 'EventOccurrenceStateResponse');

    final status = _readString(json, 'status');
    _validateStatus(status);
    final source = _readString(json, 'source');
    _validateSource(source);
    return EventOccurrenceStateResponseDto(
      id: _readString(json, 'id'),
      eventId: _readString(json, 'event_id'),
      occurrenceStartAt: _readDateTime(json, 'occurrence_start_at'),
      status: status,
      completedAt: _readOptionalDateTime(json, 'completed_at'),
      note: _readOptionalString(json, 'note'),
      source: source,
      createdAt: _readDateTime(json, 'created_at'),
      updatedAt: _readDateTime(json, 'updated_at'),
      deletedAt: _readOptionalDateTime(json, 'deleted_at'),
    );
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException(
      'EventOccurrenceStateResponse.$key must be non-empty string.',
    );
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException(
      'EventOccurrenceStateResponse.$key must be string or null.',
    );
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException(
      'EventOccurrenceStateResponse.$key must be date-time string.',
    );
  }

  static DateTime? _readOptionalDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException(
      'EventOccurrenceStateResponse.$key must be date-time string or null.',
    );
  }

  static void _validateStatus(String value) {
    const allowed = {'completed', 'skipped', 'cancelled'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown EventOccurrenceStatus: $value');
    }
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
      throw FormatException('Unknown DataSource: $value');
    }
  }
}

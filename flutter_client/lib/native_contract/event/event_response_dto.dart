import '../shared/contract_json_object.dart';

class EventResponseDto {
  const EventResponseDto({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.isAllDay,
    required this.hasRecurrence,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.content,
    this.recurrenceId,
    this.categoryId,
    this.importance,
    this.location,
    this.timezone,
    this.completedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String? content;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final bool hasRecurrence;
  final String status;
  final DateTime? completedAt;
  final String? recurrenceId;
  final String? categoryId;
  final String? importance;
  final String? location;
  final String? timezone;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory EventResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'id',
      'title',
      'content',
      'start_at',
      'end_at',
      'is_all_day',
      'has_recurrence',
      'status',
      'completed_at',
      'recurrence_id',
      'category_id',
      'importance',
      'location',
      'timezone',
      'source',
      'created_at',
      'updated_at',
      'deleted_at',
    }, 'EventResponse');
    ContractJsonObject.requireKeys(json, {
      'id',
      'title',
      'start_at',
      'end_at',
      'is_all_day',
      'has_recurrence',
      'status',
      'source',
      'created_at',
      'updated_at',
    }, 'EventResponse');

    final importance = _readOptionalString(json, 'importance');
    if (importance != null) {
      _validateImportance(importance);
    }
    final source = _readString(json, 'source');
    _validateSource(source);
    final status = _readString(json, 'status');
    _validateEventStatus(status);
    return EventResponseDto(
      id: _readString(json, 'id'),
      title: _readString(json, 'title'),
      content: _readOptionalString(json, 'content'),
      startAt: _readDateTime(json, 'start_at'),
      endAt: _readDateTime(json, 'end_at'),
      isAllDay: _readBool(json, 'is_all_day'),
      hasRecurrence: _readBool(json, 'has_recurrence'),
      status: status,
      completedAt: _readOptionalDateTime(json, 'completed_at'),
      recurrenceId: _readOptionalString(json, 'recurrence_id'),
      categoryId: _readOptionalString(json, 'category_id'),
      importance: importance,
      location: _readOptionalString(json, 'location'),
      timezone: _readOptionalString(json, 'timezone'),
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
    throw FormatException('EventResponse.$key must be non-empty string.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('EventResponse.$key must be string or null.');
  }

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('EventResponse.$key must be bool.');
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException('EventResponse.$key must be date-time string.');
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
      'EventResponse.$key must be date-time string or null.',
    );
  }

  static void _validateImportance(String value) {
    const allowed = {
      'unimportant_noturgent',
      'important_noturgent',
      'unimportant_urgent',
      'important_urgent',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown Importance: $value');
    }
  }

  static void _validateSource(String value) {
    const allowed = {'manual', 'ai_extraction', 'sync', 'import', 'wechat'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown DataSource: $value');
    }
  }

  static void _validateEventStatus(String value) {
    const allowed = {'active', 'completed', 'cancelled', 'archived'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown EventStatus: $value');
    }
  }
}

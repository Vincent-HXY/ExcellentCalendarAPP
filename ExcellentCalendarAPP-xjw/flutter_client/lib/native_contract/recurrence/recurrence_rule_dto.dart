class RecurrenceRuleDto {
  const RecurrenceRuleDto({
    required this.frequency,
    required this.interval,
    required this.startAt,
    required this.timezone,
    this.daysOfWeek = const [],
    this.dayOfMonth,
    this.monthOfYear,
    this.endAt,
    this.count,
    this.rrule,
  });

  final String frequency;
  final int interval;
  final List<int> daysOfWeek;
  final int? dayOfMonth;
  final int? monthOfYear;
  final DateTime startAt;
  final DateTime? endAt;
  final int? count;
  final String? timezone;
  final String? rrule;

  Map<String, dynamic> toJson() {
    _validateFrequency(frequency);
    return {
      'frequency': frequency,
      'interval': interval,
      'days_of_week': daysOfWeek,
      'day_of_month': dayOfMonth,
      'month_of_year': monthOfYear,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt?.toUtc().toIso8601String(),
      'count': count,
      'timezone': timezone,
      'rrule': rrule,
    };
  }

  factory RecurrenceRuleDto.fromJson(Map<String, dynamic> json) {
    final frequency = _readString(json, 'frequency');
    _validateFrequency(frequency);
    return RecurrenceRuleDto(
      frequency: frequency,
      interval: _readInt(json, 'interval'),
      daysOfWeek: _readIntList(json, 'days_of_week'),
      dayOfMonth: _readOptionalInt(json, 'day_of_month'),
      monthOfYear: _readOptionalInt(json, 'month_of_year'),
      startAt: _readDateTime(json, 'start_at'),
      endAt: _readOptionalDateTime(json, 'end_at'),
      count: _readOptionalInt(json, 'count'),
      timezone: _readOptionalString(json, 'timezone'),
      rrule: _readOptionalString(json, 'rrule'),
    );
  }

  static void _validateFrequency(String value) {
    const allowed = {'daily', 'weekly', 'monthly', 'yearly', 'custom'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown RecurrenceFrequency: $value');
    }
  }

  static String _readString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('RecurrenceRule.$key must be non-empty string.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('RecurrenceRule.$key must be string or null.');
  }

  static int _readInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('RecurrenceRule.$key must be integer.');
  }

  static int? _readOptionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw FormatException('RecurrenceRule.$key must be integer or null.');
  }

  static List<int> _readIntList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return const [];
    }
    if (value is List && value.every((item) => item is int)) {
      return value.cast<int>();
    }
    throw FormatException('RecurrenceRule.$key must be integer array.');
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException('RecurrenceRule.$key must be date-time string.');
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
      'RecurrenceRule.$key must be date-time string or null.',
    );
  }
}

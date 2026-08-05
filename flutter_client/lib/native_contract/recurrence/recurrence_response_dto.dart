import '../shared/contract_value.dart';

class RecurrenceResponseDto {
  const RecurrenceResponseDto({
    required this.recurrenceId,
    required this.revision,
    required this.frequency,
    required this.interval,
    required this.startAt,
    required this.startDate,
    required this.timezone,
    required this.dayOfMonth,
    required this.daysOfWeek,
    required this.createdAt,
  });

  static const _keys = {
    'recurrence_id',
    'revision',
    'frequency',
    'interval',
    'start_at',
    'start_date',
    'timezone',
    'day_of_month',
    'days_of_week',
    'month_of_year',
    'end_at',
    'count',
    'created_at',
  };
  static const _frequencies = {'daily', 'weekly', 'monthly'};

  final String recurrenceId;
  final int revision;
  final String frequency;
  final int interval;
  final DateTime? startAt;
  final String? startDate;
  final String timezone;
  final int? dayOfMonth;
  final List<int> daysOfWeek;
  final DateTime createdAt;

  factory RecurrenceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'RecurrenceResponse');
    if (json['month_of_year'] != null ||
        json['end_at'] != null ||
        json['count'] != null) {
      throw const FormatException(
        'RecurrenceResponse reserved v2 fields must be null.',
      );
    }

    final frequency = ContractValue.nonEmptyString(
      json,
      'frequency',
      'RecurrenceResponse',
    );
    ContractValue.validateEnum(
      frequency,
      _frequencies,
      'RecurrenceResponse.frequency',
    );
    final interval = ContractValue.integer(
      json,
      'interval',
      'RecurrenceResponse',
    );
    if (interval != 1) {
      throw const FormatException('RecurrenceResponse.interval must be 1.');
    }

    final startAt = ContractValue.optionalUtcDateTime(
      json,
      'start_at',
      'RecurrenceResponse',
      wholeSecond: true,
    );
    final startDate = ContractValue.optionalLocalDate(
      json,
      'start_date',
      'RecurrenceResponse',
    );
    if ((startAt == null) == (startDate == null)) {
      throw const FormatException(
        'RecurrenceResponse must contain exactly one start shape.',
      );
    }

    final dayOfMonth = ContractValue.optionalInteger(
      json,
      'day_of_month',
      'RecurrenceResponse',
      minimum: 1,
      maximum: 31,
    );
    final daysOfWeek = ContractValue.integerList(
      json,
      'days_of_week',
      'RecurrenceResponse',
      minimum: 1,
      maximum: 7,
      maxItems: 1,
      unique: true,
    );
    switch (frequency) {
      case 'daily':
        if (dayOfMonth != null || daysOfWeek.isNotEmpty) {
          throw const FormatException('Daily recurrence anchors are invalid.');
        }
        break;
      case 'weekly':
        if (dayOfMonth != null || daysOfWeek.length != 1) {
          throw const FormatException('Weekly recurrence anchors are invalid.');
        }
        break;
      case 'monthly':
        if (dayOfMonth == null || daysOfWeek.isNotEmpty) {
          throw const FormatException(
            'Monthly recurrence anchors are invalid.',
          );
        }
        break;
    }

    return RecurrenceResponseDto(
      recurrenceId: ContractValue.nonEmptyString(
        json,
        'recurrence_id',
        'RecurrenceResponse',
      ),
      revision: ContractValue.integer(
        json,
        'revision',
        'RecurrenceResponse',
        minimum: 1,
      ),
      frequency: frequency,
      interval: interval,
      startAt: startAt,
      startDate: startDate,
      timezone: ContractValue.nonEmptyString(
        json,
        'timezone',
        'RecurrenceResponse',
      ),
      dayOfMonth: dayOfMonth,
      daysOfWeek: daysOfWeek,
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'RecurrenceResponse',
      ),
    );
  }
}

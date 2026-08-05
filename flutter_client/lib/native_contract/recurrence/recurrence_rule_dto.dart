import '../shared/contract_value.dart';

class EventRecurrenceRuleInputDto {
  const EventRecurrenceRuleInputDto({
    required this.frequency,
    this.interval = 1,
    this.endAt,
    this.count,
  });

  static const frequencies = {'daily', 'weekly', 'monthly', 'yearly', 'custom'};

  final String frequency;
  final int interval;
  final DateTime? endAt;
  final int? count;

  Map<String, dynamic> toJson() {
    ContractValue.validateEnum(frequency, frequencies, 'RecurrenceFrequency');
    if (interval != 1) {
      throw const FormatException(
        'EventRecurrenceRuleInput.interval must be 1.',
      );
    }
    if (endAt != null || count != null) {
      throw const FormatException(
        'EventRecurrenceRuleInput must be infinite in Contract v2.',
      );
    }
    return {
      'frequency': frequency,
      'interval': interval,
      'end_at': null,
      'count': null,
    };
  }
}

class RecurrenceRuleDto extends EventRecurrenceRuleInputDto {
  const RecurrenceRuleDto({
    required super.frequency,
    super.interval,
    super.endAt,
    super.count,
  });
}

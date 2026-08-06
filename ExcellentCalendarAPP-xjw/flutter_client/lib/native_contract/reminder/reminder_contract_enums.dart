enum ReminderTargetType {
  event('event'),
  habit('habit'),
  anniversary('anniversary');

  const ReminderTargetType(this.wireValue);

  final String wireValue;

  static ReminderTargetType fromWireValue(String value) {
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () =>
          throw FormatException('Unknown Reminder target_type: $value'),
    );
  }
}

enum ReminderMethod {
  ring('ring'),
  popup('popup'),
  wechat('wechat');

  const ReminderMethod(this.wireValue);

  final String wireValue;

  static ReminderMethod fromWireValue(String value) {
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw FormatException('Unknown Reminder method: $value'),
    );
  }
}

enum ReminderStatus {
  pending('pending'),
  scheduled('scheduled'),
  sent('sent'),
  failed('failed'),
  cancelled('cancelled');

  const ReminderStatus(this.wireValue);

  final String wireValue;

  static ReminderStatus fromWireValue(String value) {
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw FormatException('Unknown Reminder status: $value'),
    );
  }
}

enum ReminderSource {
  manual('manual'),
  automatic('auto'),
  aiExtraction('ai_extraction'),
  sync('sync'),
  import('import'),
  wechat('wechat');

  const ReminderSource(this.wireValue);

  final String wireValue;

  static ReminderSource fromWireValue(String value) {
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw FormatException('Unknown Reminder source: $value'),
    );
  }
}

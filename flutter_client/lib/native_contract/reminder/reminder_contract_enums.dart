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
  cancelled('cancelled'),
  expired('expired');

  const ReminderStatus(this.wireValue);

  final String wireValue;

  static ReminderStatus fromWireValue(String value) {
    return values.firstWhere(
      (item) => item.wireValue == value,
      orElse: () => throw FormatException('Unknown Reminder status: $value'),
    );
  }
}

enum ReminderCancellationReason {
  userCancelled('user_cancelled'),
  eventCompleted('event_completed'),
  occurrenceCompleted('occurrence_completed'),
  occurrenceSkipped('occurrence_skipped'),
  occurrenceCancelled('occurrence_cancelled'),
  occurrenceReopened('occurrence_reopened'),
  seriesCompleted('series_completed'),
  seriesCancelled('series_cancelled'),
  seriesDeleted('series_deleted'),
  seriesUpdated('series_updated');

  const ReminderCancellationReason(this.wireValue);
  final String wireValue;

  static ReminderCancellationReason fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown Reminder cancellation reason: $value',
        ),
      );
}

enum ReminderExpirationReason {
  recoveryWindowElapsed('recovery_window_elapsed');

  const ReminderExpirationReason(this.wireValue);
  final String wireValue;

  static ReminderExpirationReason fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () =>
            throw FormatException('Unknown Reminder expiration reason: $value'),
      );
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

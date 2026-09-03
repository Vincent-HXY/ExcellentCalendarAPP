enum CalendarSection {
  event('event'),
  habit('habit'),
  anniversary('anniversary');

  const CalendarSection(this.wireValue);
  final String wireValue;

  static CalendarSection fromWireValue(String value) => switch (value) {
    'event' => CalendarSection.event,
    'habit' => CalendarSection.habit,
    'anniversary' => CalendarSection.anniversary,
    _ => throw FormatException('Unknown CalendarSection: $value'),
  };
}

enum CalendarEventItemStatus {
  pending('pending'),
  inProgress('in_progress'),
  overdue('overdue'),
  completed('completed'),
  skipped('skipped');

  const CalendarEventItemStatus(this.wireValue);
  final String wireValue;

  static CalendarEventItemStatus fromWireValue(String value) => switch (value) {
    'pending' => CalendarEventItemStatus.pending,
    'in_progress' => CalendarEventItemStatus.inProgress,
    'overdue' => CalendarEventItemStatus.overdue,
    'completed' => CalendarEventItemStatus.completed,
    'skipped' => CalendarEventItemStatus.skipped,
    _ => throw FormatException('Unknown CalendarEventItemStatus: $value'),
  };
}

enum CalendarEventDayDisplay {
  allDay('all_day'),
  startsAt('starts_at'),
  continues('continues'),
  endsAt('ends_at');

  const CalendarEventDayDisplay(this.wireValue);
  final String wireValue;

  static CalendarEventDayDisplay fromWireValue(String value) => switch (value) {
    'all_day' => CalendarEventDayDisplay.allDay,
    'starts_at' => CalendarEventDayDisplay.startsAt,
    'continues' => CalendarEventDayDisplay.continues,
    'ends_at' => CalendarEventDayDisplay.endsAt,
    _ => throw FormatException('Unknown CalendarEventDayDisplay: $value'),
  };
}

enum CalendarHabitItemStatus {
  upcoming('upcoming'),
  absent('absent'),
  partial('partial'),
  done('done'),
  skipped('skipped'),
  missed('missed');

  const CalendarHabitItemStatus(this.wireValue);
  final String wireValue;

  static CalendarHabitItemStatus fromWireValue(String value) => switch (value) {
    'upcoming' => CalendarHabitItemStatus.upcoming,
    'absent' => CalendarHabitItemStatus.absent,
    'partial' => CalendarHabitItemStatus.partial,
    'done' => CalendarHabitItemStatus.done,
    'skipped' => CalendarHabitItemStatus.skipped,
    'missed' => CalendarHabitItemStatus.missed,
    _ => throw FormatException('Unknown CalendarHabitItemStatus: $value'),
  };
}

enum CalendarAnniversaryImportance {
  unimportantNotUrgent('unimportant_noturgent'),
  importantNotUrgent('important_noturgent'),
  unimportantUrgent('unimportant_urgent'),
  importantUrgent('important_urgent');

  const CalendarAnniversaryImportance(this.wireValue);
  final String wireValue;

  static CalendarAnniversaryImportance? fromNullableWireValue(
    String? value,
  ) => switch (value) {
    null => null,
    'unimportant_noturgent' =>
      CalendarAnniversaryImportance.unimportantNotUrgent,
    'important_noturgent' => CalendarAnniversaryImportance.importantNotUrgent,
    'unimportant_urgent' => CalendarAnniversaryImportance.unimportantUrgent,
    'important_urgent' => CalendarAnniversaryImportance.importantUrgent,
    _ => throw FormatException('Unknown CalendarAnniversaryImportance: $value'),
  };
}

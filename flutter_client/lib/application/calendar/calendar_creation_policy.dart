abstract final class CalendarCreationPolicy {
  static DateTime habitInitialDate({
    required DateTime selectedDate,
    required DateTime now,
  }) {
    final selected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    return selected.isBefore(today) ? today : selected;
  }
}

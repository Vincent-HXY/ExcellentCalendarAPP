enum CalendarViewMode { week, month }

class CalendarDateRange {
  const CalendarDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  int get dayCount => end.difference(start).inDays;

  bool contains(DateTime value) {
    final date = CalendarDateMath.dateOnly(value);
    return !date.isBefore(start) && date.isBefore(end);
  }
}

abstract final class CalendarDateMath {
  static DateTime dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static DateTime parseDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw FormatException('Invalid local date: $value');
    final result = DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    if (formatDate(result) != value) {
      throw FormatException('Invalid local date: $value');
    }
    return result;
  }

  static String formatDate(DateTime value) {
    final date = dateOnly(value);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static bool isSameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static DateTime startOfWeek(DateTime value) {
    final date = dateOnly(value);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  static CalendarDateRange visibleRange(
    DateTime anchor,
    CalendarViewMode mode,
  ) => switch (mode) {
    CalendarViewMode.week => _weekRange(anchor),
    CalendarViewMode.month => _monthRange(anchor),
  };

  static CalendarDateRange _weekRange(DateTime anchor) {
    final start = startOfWeek(anchor);
    return CalendarDateRange(
      start: start,
      end: start.add(const Duration(days: 7)),
    );
  }

  static CalendarDateRange _monthRange(DateTime anchor) {
    final date = dateOnly(anchor);
    final first = DateTime.utc(date.year, date.month);
    final last = DateTime.utc(date.year, date.month + 1, 0);
    final start = startOfWeek(first);
    final end = startOfWeek(last).add(const Duration(days: 7));
    return CalendarDateRange(start: start, end: end);
  }

  static DateTime addMonthsClamped(DateTime value, int delta) {
    final date = dateOnly(value);
    final totalMonths = date.year * 12 + date.month - 1 + delta;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, date.day.clamp(1, lastDay));
  }

  static DateTime inMonthKeepingDay({
    required int year,
    required int month,
    required int preferredDay,
  }) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return DateTime.utc(year, month, preferredDay.clamp(1, lastDay));
  }

  static List<DateTime> dates(CalendarDateRange range) => List.unmodifiable([
    for (
      var date = range.start;
      date.isBefore(range.end);
      date = date.add(const Duration(days: 1))
    )
      date,
  ]);
}

import 'package:excellent_calendar/application/calendar/calendar_date_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('month arithmetic crosses both year boundaries', () {
    expect(
      CalendarDateMath.addMonthsClamped(DateTime.utc(2026, 12, 15), 1),
      DateTime.utc(2027, 1, 15),
    );
    expect(
      CalendarDateMath.addMonthsClamped(DateTime.utc(2026, 1, 15), -1),
      DateTime.utc(2025, 12, 15),
    );
  });

  test('month arithmetic clamps day 31 in short and leap-year months', () {
    expect(
      CalendarDateMath.addMonthsClamped(DateTime.utc(2024, 1, 31), 1),
      DateTime.utc(2024, 2, 29),
    );
    expect(
      CalendarDateMath.addMonthsClamped(DateTime.utc(2025, 1, 31), 1),
      DateTime.utc(2025, 2, 28),
    );
    expect(
      CalendarDateMath.addMonthsClamped(DateTime.utc(2026, 3, 31), 1),
      DateTime.utc(2026, 4, 30),
    );
  });

  test('week and six-row month grids always start on Monday', () {
    final week = CalendarDateMath.visibleRange(
      DateTime.utc(2026, 9, 3),
      CalendarViewMode.week,
    );
    expect(week.start, DateTime.utc(2026, 8, 31));
    expect(week.start.weekday, DateTime.monday);
    expect(week.dayCount, 7);

    final sixRows = CalendarDateMath.visibleRange(
      DateTime.utc(2020, 8, 15),
      CalendarViewMode.month,
    );
    expect(sixRows.start, DateTime.utc(2020, 7, 27));
    expect(sixRows.end, DateTime.utc(2020, 9, 7));
    expect(sixRows.start.weekday, DateTime.monday);
    expect(sixRows.dayCount, 42);
  });

  test('strict local-date parser rejects rollover and preserves leap day', () {
    expect(CalendarDateMath.parseDate('2024-02-29'), DateTime.utc(2024, 2, 29));
    expect(
      () => CalendarDateMath.parseDate('2025-02-29'),
      throwsFormatException,
    );
    expect(
      () => CalendarDateMath.parseDate('2026-2-03'),
      throwsFormatException,
    );
  });
}

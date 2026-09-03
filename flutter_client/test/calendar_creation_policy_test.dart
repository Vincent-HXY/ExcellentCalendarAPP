import 'package:excellent_calendar/application/calendar/calendar_creation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 31, 18, 45);

  test('past Habit date is clamped to the local natural today', () {
    expect(
      CalendarCreationPolicy.habitInitialDate(
        selectedDate: DateTime.utc(2026, 8, 20),
        now: now,
      ),
      DateTime(2026, 8, 31),
    );
  });

  test('today remains today without carrying wall-clock time', () {
    expect(
      CalendarCreationPolicy.habitInitialDate(
        selectedDate: DateTime.utc(2026, 8, 31),
        now: now,
      ),
      DateTime(2026, 8, 31),
    );
  });

  test('future Habit date remains the selected natural date', () {
    expect(
      CalendarCreationPolicy.habitInitialDate(
        selectedDate: DateTime.utc(2026, 9, 8),
        now: now,
      ),
      DateTime(2026, 9, 8),
    );
  });
}

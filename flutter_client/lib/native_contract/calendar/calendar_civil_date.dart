import '../shared/contract_value.dart';

/// A Gregorian calendar date with no time, offset, or instant semantics.
///
/// UTC [DateTime] values are used only as an internal, host-timezone-independent
/// arithmetic coordinate. They are never exposed as moments on a timeline.
final class CalendarCivilDate {
  const CalendarCivilDate._(this.year, this.month, this.day);

  factory CalendarCivilDate.parse(String value, {required String field}) {
    ContractValue.validateLocalDate(value, field: field);
    final parts = value.split('-');
    return CalendarCivilDate._(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  final int year;
  final int month;
  final int day;

  int daysUntil(CalendarCivilDate other) =>
      other._utcCoordinate.difference(_utcCoordinate).inDays;

  bool isBefore(CalendarCivilDate other) => daysUntil(other) > 0;

  CalendarCivilDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day + days);
    return CalendarCivilDate._(shifted.year, shifted.month, shifted.day);
  }

  String get wireValue =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  DateTime get _utcCoordinate => DateTime.utc(year, month, day);
}

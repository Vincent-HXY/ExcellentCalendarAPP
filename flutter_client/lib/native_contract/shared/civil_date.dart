final class CivilDate implements Comparable<CivilDate> {
  const CivilDate(this.year, this.month, this.day);

  factory CivilDate.fromDateTime(DateTime value) =>
      CivilDate(value.year, value.month, value.day);

  factory CivilDate.parse(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('Invalid civil date.');
    final result = CivilDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    final normalized = DateTime.utc(result.year, result.month, result.day);
    if (normalized.year != result.year ||
        normalized.month != result.month ||
        normalized.day != result.day) {
      throw const FormatException('Invalid civil date.');
    }
    return result;
  }

  final int year;
  final int month;
  final int day;

  CivilDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return CivilDate(shifted.year, shifted.month, shifted.day);
  }

  CivilDate addMonthsClamped(int months) {
    final monthIndex = month - 1 + months;
    final targetYear = year + monthIndex ~/ 12;
    final targetMonth = monthIndex % 12 + 1;
    final lastDay = DateTime.utc(targetYear, targetMonth + 1, 0).day;
    return CivilDate(targetYear, targetMonth, day.clamp(1, lastDay));
  }

  CivilDate addYearsClamped(int years) {
    final targetYear = year + years;
    final lastDay = DateTime.utc(targetYear, month + 1, 0).day;
    return CivilDate(targetYear, month, day.clamp(1, lastDay));
  }

  int inclusiveDaysUntil(CivilDate end) =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(year, month, day)).inDays +
      1;

  DateTime toLocalDateTime() => DateTime(year, month, day);

  String format() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CivilDate other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) return yearComparison;
    final monthComparison = month.compareTo(other.month);
    return monthComparison != 0 ? monthComparison : day.compareTo(other.day);
  }
}

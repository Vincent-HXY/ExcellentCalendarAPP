class LocalWallDateTime implements Comparable<LocalWallDateTime> {
  const LocalWallDateTime({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
  });

  factory LocalWallDateTime.fromDateTimeComponents(DateTime value) {
    return LocalWallDateTime(
      year: value.year,
      month: value.month,
      day: value.day,
      hour: value.hour,
      minute: value.minute,
      second: value.second,
    );
  }

  factory LocalWallDateTime.fromLocalDate(String value) {
    return LocalWallDateTime.parse('${value}T00:00:00');
  }

  factory LocalWallDateTime.parse(String value) {
    final match = _pattern.firstMatch(value);
    if (match == null) {
      throw const FormatException(
        'Local wall date-time must use YYYY-MM-DDTHH:mm:ss.',
      );
    }
    final result = LocalWallDateTime(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
      hour: int.parse(match.group(4)!),
      minute: int.parse(match.group(5)!),
      second: int.parse(match.group(6)!),
    );
    final normalized = result.toComponentDateTime();
    if (result.year < 1 ||
        result.year > 9999 ||
        normalized.year != result.year ||
        normalized.month != result.month ||
        normalized.day != result.day ||
        normalized.hour != result.hour ||
        normalized.minute != result.minute ||
        normalized.second != result.second) {
      throw const FormatException('Local wall date-time is invalid.');
    }
    return result;
  }

  static final RegExp _pattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$',
  );

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  /// A component container only. Its UTC flag must not be interpreted as an instant.
  DateTime toComponentDateTime() {
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  @override
  int compareTo(LocalWallDateTime other) {
    return toComponentDateTime().compareTo(other.toComponentDateTime());
  }

  bool isBefore(LocalWallDateTime other) => compareTo(other) < 0;

  @override
  String toString() {
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}T'
        '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}:'
        '${second.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) {
    return other is LocalWallDateTime && compareTo(other) == 0;
  }

  @override
  int get hashCode => Object.hash(year, month, day, hour, minute, second);
}

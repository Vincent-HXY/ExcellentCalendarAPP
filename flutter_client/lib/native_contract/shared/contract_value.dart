import 'contract_json_object.dart';

abstract final class ContractValue {
  static final RegExp _utcDateTimePattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?Z$',
  );
  static final RegExp _localDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static String nonEmptyString(
    Map<String, dynamic> json,
    String key,
    String parent,
  ) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('$parent.$key must be a non-empty string.');
  }

  static String? optionalString(
    Map<String, dynamic> json,
    String key,
    String parent,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('$parent.$key must be string or null.');
  }

  static bool boolean(Map<String, dynamic> json, String key, String parent) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('$parent.$key must be bool.');
  }

  static int integer(
    Map<String, dynamic> json,
    String key,
    String parent, {
    int? minimum,
    int? maximum,
  }) {
    final value = json[key];
    if (value is! int ||
        (minimum != null && value < minimum) ||
        (maximum != null && value > maximum)) {
      throw FormatException('$parent.$key must be an integer in range.');
    }
    return value;
  }

  static int? optionalInteger(
    Map<String, dynamic> json,
    String key,
    String parent, {
    int? minimum,
    int? maximum,
  }) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int ||
        (minimum != null && value < minimum) ||
        (maximum != null && value > maximum)) {
      throw FormatException(
        '$parent.$key must be an integer in range or null.',
      );
    }
    return value;
  }

  static List<String> stringList(
    Map<String, dynamic> json,
    String key,
    String parent, {
    Set<String>? allowed,
    bool unique = false,
    bool nonEmpty = false,
  }) {
    final value = json[key];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$parent.$key must be a string array.');
    }
    final result = List<String>.unmodifiable(value.cast<String>());
    if (nonEmpty && result.isEmpty) {
      throw FormatException('$parent.$key must not be empty.');
    }
    if (unique && result.toSet().length != result.length) {
      throw FormatException('$parent.$key must contain unique values.');
    }
    if (allowed != null && result.any((item) => !allowed.contains(item))) {
      throw FormatException('$parent.$key contains an unknown enum value.');
    }
    return result;
  }

  static List<int> integerList(
    Map<String, dynamic> json,
    String key,
    String parent, {
    int? minimum,
    int? maximum,
    int? maxItems,
    bool unique = false,
  }) {
    final value = json[key];
    if (value is! List || value.any((item) => item is! int)) {
      throw FormatException('$parent.$key must be an integer array.');
    }
    final result = List<int>.unmodifiable(value.cast<int>());
    if (maxItems != null && result.length > maxItems) {
      throw FormatException('$parent.$key contains too many values.');
    }
    if (unique && result.toSet().length != result.length) {
      throw FormatException('$parent.$key must contain unique values.');
    }
    if (result.any(
      (item) =>
          (minimum != null && item < minimum) ||
          (maximum != null && item > maximum),
    )) {
      throw FormatException('$parent.$key contains an out-of-range value.');
    }
    return result;
  }

  static DateTime utcDateTime(
    Map<String, dynamic> json,
    String key,
    String parent, {
    bool wholeSecond = false,
  }) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('$parent.$key must be a UTC date-time string.');
    }
    return parseUtcDateTime(
      value,
      field: '$parent.$key',
      wholeSecond: wholeSecond,
    );
  }

  static DateTime? optionalUtcDateTime(
    Map<String, dynamic> json,
    String key,
    String parent, {
    bool wholeSecond = false,
  }) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException(
        '$parent.$key must be a UTC date-time string or null.',
      );
    }
    return parseUtcDateTime(
      value,
      field: '$parent.$key',
      wholeSecond: wholeSecond,
    );
  }

  static DateTime parseUtcDateTime(
    String value, {
    required String field,
    bool wholeSecond = false,
  }) {
    final match = _utcDateTimePattern.firstMatch(value);
    if (match == null || (wholeSecond && match.group(7) != null)) {
      throw FormatException('$field must be an ISO 8601 UTC instant.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    if (!_validDate(year, month, day) ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw FormatException('$field must be a valid UTC instant.');
    }
    return DateTime.parse(value).toUtc();
  }

  static String localDate(
    Map<String, dynamic> json,
    String key,
    String parent,
  ) {
    final value = json[key];
    if (value is String) {
      validateLocalDate(value, field: '$parent.$key');
      return value;
    }
    throw FormatException('$parent.$key must be a local date string.');
  }

  static String? optionalLocalDate(
    Map<String, dynamic> json,
    String key,
    String parent,
  ) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) {
      validateLocalDate(value, field: '$parent.$key');
      return value;
    }
    throw FormatException('$parent.$key must be a local date string or null.');
  }

  static void validateLocalDate(String value, {required String field}) {
    final match = _localDatePattern.firstMatch(value);
    if (match == null ||
        !_validDate(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        )) {
      throw FormatException('$field must use a valid YYYY-MM-DD date.');
    }
  }

  static String formatUtcSecond(DateTime value, {required String field}) {
    final utc = value.toUtc();
    if (utc.millisecond != 0 || utc.microsecond != 0) {
      throw FormatException('$field must be fixed to a whole second.');
    }
    return '${_four(utc.year)}-${_two(utc.month)}-${_two(utc.day)}T'
        '${_two(utc.hour)}:${_two(utc.minute)}:${_two(utc.second)}Z';
  }

  static String formatUtcDateTime(DateTime value, {required String field}) {
    final encoded = value.toUtc().toIso8601String();
    if (!_utcDateTimePattern.hasMatch(encoded)) {
      throw FormatException('$field must be an ISO 8601 UTC instant.');
    }
    return encoded;
  }

  static DateTime localDateAsDateTime(String value, {required String field}) {
    validateLocalDate(value, field: field);
    final parts = value.split('-').map(int.parse).toList(growable: false);
    return DateTime(parts[0], parts[1], parts[2]);
  }

  static void requireExactKeys(
    Map<String, dynamic> json,
    Set<String> keys,
    String parent,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, keys, parent);
    ContractJsonObject.requireKeys(json, keys, parent);
  }

  static void validateEnum(String value, Set<String> allowed, String field) {
    if (!allowed.contains(value)) {
      throw FormatException('Unknown $field: $value');
    }
  }

  static bool _validDate(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      return false;
    }
    final daysInMonth = DateTime.utc(year, month + 1, 0).day;
    return day <= daysInMonth;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
  static String _four(int value) => value.toString().padLeft(4, '0');
}

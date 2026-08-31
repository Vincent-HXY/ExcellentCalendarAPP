import '../shared/contract_value.dart';

abstract final class HabitContractValue {
  static const maxSafeInteger = 9007199254740991;

  static Map<String, dynamic> object(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('$field must be an object.');
  }

  static List<Map<String, dynamic>> objectList(
    Object? value,
    String field, {
    int? maximum,
  }) {
    if (value is! List ||
        value.any((item) => item is! Map<String, dynamic>) ||
        (maximum != null && value.length > maximum)) {
      throw FormatException('$field must be a bounded object array.');
    }
    return List<Map<String, dynamic>>.unmodifiable(
      value.cast<Map<String, dynamic>>(),
    );
  }

  static double ratio(
    Map<String, dynamic> json,
    String key,
    String parent, {
    bool nullable = false,
  }) {
    final value = json[key];
    if (nullable && value == null) return double.nan;
    if (value is num && value.isFinite && value >= 0 && value <= 1) {
      return value.toDouble();
    }
    throw FormatException('$parent.$key must be a ratio.');
  }

  static String limitedString(
    Map<String, dynamic> json,
    String key,
    String parent, {
    required int maximumCodePoints,
    bool allowEmpty = false,
  }) {
    final value = json[key];
    if (value is! String ||
        (!allowEmpty && value.isEmpty) ||
        value.runes.length > maximumCodePoints) {
      throw FormatException('$parent.$key has an invalid text length.');
    }
    return value;
  }

  static String? optionalLimitedString(
    Map<String, dynamic> json,
    String key,
    String parent, {
    required int maximumCodePoints,
  }) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String || value.runes.length > maximumCodePoints) {
      throw FormatException('$parent.$key has an invalid text length.');
    }
    return value;
  }

  static void uuidOrNull(String? value, String field) {
    if (value == null) return;
    ContractValue.uuid({'value': value}, 'value', field);
  }

  static String localTime(
    Map<String, dynamic> json,
    String key,
    String parent,
  ) {
    final value = json[key];
    if (value is String &&
        RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
      return value;
    }
    throw FormatException('$parent.$key must use HH:mm.');
  }

  static String utcSecond(DateTime value, String field) =>
      ContractValue.formatUtcSecond(value, field: field);
}

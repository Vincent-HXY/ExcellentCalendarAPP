class NativeJsonNormalizer {
  const NativeJsonNormalizer._();

  static Map<String, dynamic> normalizeMap(Object? value) {
    final normalized = normalize(value);
    if (normalized is Map<String, dynamic>) {
      return normalized;
    }
    throw const FormatException('Native response must be a JSON object.');
  }

  static Object? normalize(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) {
      return value.map(normalize).toList(growable: false);
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw FormatException('Native JSON object key must be string: $key');
        }
        result[key] = normalize(entry.value);
      }
      return result;
    }
    throw FormatException(
      'Unsupported native JSON value: ${value.runtimeType}',
    );
  }
}

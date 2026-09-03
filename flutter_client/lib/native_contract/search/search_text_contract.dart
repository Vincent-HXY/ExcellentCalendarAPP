abstract final class SearchTextContract {
  static const int maximumKeywordScalars = 128;
  static const int maximumKeywordUtf8Bytes = 512;

  static SearchTextAnalysis analyze(String value) {
    var scalarCount = 0;
    var utf8Bytes = 0;
    var pendingSpace = false;
    var hasContent = false;
    final display = StringBuffer();
    final comparison = StringBuffer();
    final units = value.codeUnits;
    for (var index = 0; index < units.length; index++) {
      final first = units[index];
      late final int scalar;
      if (first >= 0xD800 && first <= 0xDBFF) {
        if (index + 1 >= units.length) {
          throw const FormatException('Search text has an isolated surrogate.');
        }
        final second = units[++index];
        if (second < 0xDC00 || second > 0xDFFF) {
          throw const FormatException('Search text has an isolated surrogate.');
        }
        scalar = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00;
      } else if (first >= 0xDC00 && first <= 0xDFFF) {
        throw const FormatException('Search text has an isolated surrogate.');
      } else {
        scalar = first;
      }
      scalarCount += 1;
      utf8Bytes += switch (scalar) {
        <= 0x7F => 1,
        <= 0x7FF => 2,
        <= 0xFFFF => 3,
        _ => 4,
      };
      if (_isFrozenWhitespace(scalar)) {
        pendingSpace = hasContent;
        continue;
      }
      if (pendingSpace) {
        display.write(' ');
        comparison.write(' ');
        pendingSpace = false;
      }
      display.writeCharCode(scalar);
      comparison.writeCharCode(_asciiFold(scalar));
      hasContent = true;
    }
    return SearchTextAnalysis(
      scalarCount: scalarCount,
      utf8Bytes: utf8Bytes,
      normalizedDisplay: display.toString(),
      comparisonKey: comparison.toString(),
    );
  }

  static bool isBlank(String value) {
    try {
      return analyze(value).normalizedDisplay.isEmpty;
    } on FormatException {
      return false;
    }
  }

  static String normalizeForWire(String value) {
    try {
      return analyze(value).normalizedDisplay;
    } on FormatException {
      return value;
    }
  }

  static bool _isFrozenWhitespace(int scalar) =>
      (scalar >= 0x0009 && scalar <= 0x000D) ||
      scalar == 0x0020 ||
      scalar == 0x0085 ||
      scalar == 0x00A0 ||
      scalar == 0x1680 ||
      (scalar >= 0x2000 && scalar <= 0x200A) ||
      scalar == 0x2028 ||
      scalar == 0x2029 ||
      scalar == 0x202F ||
      scalar == 0x205F ||
      scalar == 0x3000;

  static int _asciiFold(int scalar) =>
      scalar >= 65 && scalar <= 90 ? scalar + 32 : scalar;
}

class SearchTextAnalysis {
  const SearchTextAnalysis({
    required this.scalarCount,
    required this.utf8Bytes,
    required this.normalizedDisplay,
    required this.comparisonKey,
  });

  final int scalarCount;
  final int utf8Bytes;
  final String normalizedDisplay;
  final String comparisonKey;
}

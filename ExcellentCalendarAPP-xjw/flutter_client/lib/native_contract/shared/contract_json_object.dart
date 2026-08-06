class ContractJsonObject {
  const ContractJsonObject._();

  static void rejectUnknownKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String parent,
  ) {
    final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException('$parent contains unknown field: ${unknown.first}');
    }
  }

  static void requireKeys(
    Map<String, dynamic> json,
    Set<String> required,
    String parent,
  ) {
    final missing = required.where((key) => !json.containsKey(key)).toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        '$parent is missing required field: ${missing.first}',
      );
    }
  }
}

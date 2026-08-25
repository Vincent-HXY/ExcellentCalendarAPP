/// Non-sensitive flat user settings map (snake_case keys only).
class UserSettingsDto {
  const UserSettingsDto(this.values);

  final Map<String, dynamic> values;

  static final RegExp _keyPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
  static const _forbiddenKeys = {
    'password',
    'password_hash',
    'access_token',
    'refresh_token',
    'token_hash',
    'verification_code',
    'link_token',
    'storage_key',
  };

  factory UserSettingsDto.fromJson(Map<String, dynamic> json) {
    // UserSettings is an open flat map: every key is validated against the
    // snake_case pattern instead of a fixed allow-list.
    if (json.length > 64) {
      throw const FormatException('UserSettings has more than 64 entries.');
    }
    for (final entry in json.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!_keyPattern.hasMatch(key) || _forbiddenKeys.contains(key)) {
        throw FormatException('UserSettings contains forbidden key: $key');
      }
      if (value is! String && value is! num && value is! bool) {
        throw FormatException(
          'UserSettings.$key must be string, number, or boolean.',
        );
      }
    }
    return UserSettingsDto(Map<String, dynamic>.unmodifiable(json));
  }

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(values);

  @override
  bool operator ==(Object other) {
    if (other is! UserSettingsDto) return false;
    if (other.values.length != values.length) return false;
    for (final entry in values.entries) {
      if (other.values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    values.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

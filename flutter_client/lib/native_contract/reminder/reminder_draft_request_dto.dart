class ReminderDraftRequestDto {
  const ReminderDraftRequestDto({
    required this.targetType,
    required this.methods,
    required this.isEnabled,
    required this.source,
    this.targetId,
    this.remindAt,
    this.advanceMinutes,
    this.message,
  });

  final String targetType;
  final String? targetId;
  final DateTime? remindAt;
  final int? advanceMinutes;
  final List<String> methods;
  final String? message;
  final bool isEnabled;
  final String source;

  Map<String, dynamic> toJson() {
    _validateTargetType(targetType);
    if (remindAt == null && advanceMinutes == null) {
      throw const FormatException(
        'ReminderDraft requires remind_at or advance_minutes.',
      );
    }
    if (advanceMinutes != null && advanceMinutes! < 0) {
      throw const FormatException(
        'ReminderDraft advance_minutes must be greater than or equal to 0.',
      );
    }
    if (methods.isEmpty) {
      throw const FormatException('ReminderDraft methods must not be empty.');
    }
    if (methods.toSet().length != methods.length) {
      throw const FormatException('ReminderDraft methods must be unique.');
    }
    for (final method in methods) {
      _validateReminderMethod(method);
    }
    _validateSource(source);
    return {
      'target_type': targetType,
      'target_id': targetId,
      'remind_at': remindAt?.toUtc().toIso8601String(),
      'advance_minutes': advanceMinutes,
      'methods': methods,
      'message': message,
      'is_enabled': isEnabled,
      'source': source,
    };
  }

  static void _validateTargetType(String value) {
    const allowed = {'event', 'anniversary'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown ReminderDraft target_type: $value');
    }
  }

  static void _validateReminderMethod(String value) {
    const allowed = {'ring', 'popup', 'wechat'};
    if (!allowed.contains(value)) {
      throw FormatException('Unknown ReminderMethod: $value');
    }
  }

  static void _validateSource(String value) {
    const allowed = {
      'manual',
      'auto',
      'ai_extraction',
      'sync',
      'import',
      'wechat',
    };
    if (!allowed.contains(value)) {
      throw FormatException('Unknown ReminderDraft source: $value');
    }
  }
}

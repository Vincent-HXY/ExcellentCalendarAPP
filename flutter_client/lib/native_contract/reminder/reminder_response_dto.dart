import '../shared/contract_json_object.dart';
import 'reminder_contract_enums.dart';

class ReminderResponseDto {
  const ReminderResponseDto({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.remindAt,
    required this.methods,
    required this.isEnabled,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.advanceMinutes,
    this.message,
    this.scheduledAt,
    this.lastTriggeredAt,
    this.failureReason,
    this.deletedAt,
  });

  final String id;
  final ReminderTargetType targetType;
  final String targetId;
  final DateTime remindAt;
  final List<ReminderMethod> methods;
  final int? advanceMinutes;
  final String? message;
  final bool isEnabled;
  final ReminderStatus status;
  final DateTime? scheduledAt;
  final DateTime? lastTriggeredAt;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory ReminderResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'id',
      'target_type',
      'target_id',
      'remind_at',
      'methods',
      'advance_minutes',
      'message',
      'is_enabled',
      'status',
      'scheduled_at',
      'last_triggered_at',
      'failure_reason',
      'created_at',
      'updated_at',
      'deleted_at',
    }, 'ReminderResponse');
    ContractJsonObject.requireKeys(json, {
      'id',
      'target_type',
      'target_id',
      'remind_at',
      'methods',
      'is_enabled',
      'status',
      'created_at',
      'updated_at',
    }, 'ReminderResponse');

    final methods = _readStringList(
      json,
      'methods',
    ).map(ReminderMethod.fromWireValue).toList(growable: false);
    if (methods.isEmpty || methods.toSet().length != methods.length) {
      throw const FormatException(
        'ReminderResponse.methods must contain unique values.',
      );
    }

    return ReminderResponseDto(
      id: _readNonEmptyString(json, 'id'),
      targetType: ReminderTargetType.fromWireValue(
        _readNonEmptyString(json, 'target_type'),
      ),
      targetId: _readNonEmptyString(json, 'target_id'),
      remindAt: _readDateTime(json, 'remind_at'),
      methods: methods,
      advanceMinutes: _readOptionalNonNegativeInt(json, 'advance_minutes'),
      message: _readOptionalString(json, 'message'),
      isEnabled: _readBool(json, 'is_enabled'),
      status: ReminderStatus.fromWireValue(_readNonEmptyString(json, 'status')),
      scheduledAt: _readOptionalDateTime(json, 'scheduled_at'),
      lastTriggeredAt: _readOptionalDateTime(json, 'last_triggered_at'),
      failureReason: _readOptionalString(json, 'failure_reason'),
      createdAt: _readDateTime(json, 'created_at'),
      updatedAt: _readDateTime(json, 'updated_at'),
      deletedAt: _readOptionalDateTime(json, 'deleted_at'),
    );
  }

  static String _readNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('ReminderResponse.$key must be non-empty string.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('ReminderResponse.$key must be string or null.');
  }

  static List<String> _readStringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List && value.every((item) => item is String)) {
      return value.cast<String>();
    }
    throw FormatException('ReminderResponse.$key must be string array.');
  }

  static int? _readOptionalNonNegativeInt(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is int && value >= 0) {
      return value;
    }
    throw FormatException(
      'ReminderResponse.$key must be non-negative integer or null.',
    );
  }

  static bool _readBool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('ReminderResponse.$key must be bool.');
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException('ReminderResponse.$key must be date-time string.');
  }

  static DateTime? _readOptionalDateTime(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    throw FormatException(
      'ReminderResponse.$key must be date-time string or null.',
    );
  }
}

import '../shared/contract_json_object.dart';
import 'notification_contract_enums.dart';

class NotificationTapPayloadDto {
  const NotificationTapPayloadDto({
    required this.notificationId,
    required this.reminderId,
    required this.targetType,
    required this.targetId,
    required this.route,
    required this.openedAt,
  });

  final String notificationId;
  final String? reminderId;
  final NotificationTargetType targetType;
  final String targetId;
  final String? route;
  final DateTime openedAt;

  factory NotificationTapPayloadDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'notification_id',
      'reminder_id',
      'target_type',
      'target_id',
      'route',
      'opened_at',
    }, 'NotificationTapPayload');
    ContractJsonObject.requireKeys(json, {
      'notification_id',
      'reminder_id',
      'target_type',
      'target_id',
      'opened_at',
    }, 'NotificationTapPayload');
    final reminderId = _readOptionalString(json, 'reminder_id');
    if (reminderId != null && reminderId.isEmpty) {
      throw const FormatException('reminder_id must be non-empty or null.');
    }
    return NotificationTapPayloadDto(
      notificationId: _readNonEmptyString(json, 'notification_id'),
      reminderId: reminderId,
      targetType: NotificationTargetType.fromWireValue(
        _readNonEmptyString(json, 'target_type'),
      ),
      targetId: _readNonEmptyString(json, 'target_id'),
      route: _readOptionalString(json, 'route'),
      openedAt: _readDateTime(json, 'opened_at'),
    );
  }

  Map<String, dynamic> toJson() => {
    'notification_id': notificationId,
    'reminder_id': reminderId,
    'target_type': targetType.wireValue,
    'target_id': targetId,
    'route': route,
    'opened_at': openedAt.toUtc().toIso8601String(),
  };

  static String _readNonEmptyString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('$key must be non-empty string.');
  }

  static String? _readOptionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw FormatException('$key must be string or null.');
  }

  static DateTime _readDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) return DateTime.parse(value);
    throw FormatException('$key must be date-time string.');
  }
}

class NotificationTapPayloadResponseDto {
  const NotificationTapPayloadResponseDto({
    required this.hasPayload,
    required this.payload,
  });

  final bool hasPayload;
  final NotificationTapPayloadDto? payload;

  factory NotificationTapPayloadResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'has_payload',
      'payload',
    }, 'NotificationTapPayloadResponse');
    ContractJsonObject.requireKeys(json, {
      'has_payload',
      'payload',
    }, 'NotificationTapPayloadResponse');
    final hasPayload = json['has_payload'];
    final rawPayload = json['payload'];
    if (hasPayload is! bool) {
      throw const FormatException('has_payload must be bool.');
    }
    if (hasPayload && rawPayload is! Map<String, dynamic>) {
      throw const FormatException('payload must be object when present.');
    }
    if (!hasPayload && rawPayload != null) {
      throw const FormatException('payload must be null when absent.');
    }
    return NotificationTapPayloadResponseDto(
      hasPayload: hasPayload,
      payload: rawPayload is Map<String, dynamic>
          ? NotificationTapPayloadDto.fromJson(rawPayload)
          : null,
    );
  }
}

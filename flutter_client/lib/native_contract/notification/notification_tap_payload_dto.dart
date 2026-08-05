import '../shared/contract_value.dart';
import 'notification_contract_enums.dart';

class NotificationTapPayloadDto {
  const NotificationTapPayloadDto({
    required this.notificationId,
    required this.deliveryId,
    required this.deliveryAttemptId,
    required this.kind,
    required this.reminderId,
    required this.recoveryBatchId,
    required this.targetType,
    required this.targetId,
    required this.occurrenceKey,
    required this.route,
    required this.openedAt,
  });

  static const _keys = {
    'notification_id',
    'delivery_id',
    'delivery_attempt_id',
    'kind',
    'reminder_id',
    'recovery_batch_id',
    'target_type',
    'target_id',
    'occurrence_key',
    'route',
    'opened_at',
  };

  final String notificationId;
  final String deliveryId;
  final String deliveryAttemptId;
  final NotificationKind kind;
  final String? reminderId;
  final String? recoveryBatchId;
  final NotificationTargetType targetType;
  final String targetId;
  final String? occurrenceKey;
  final String? route;
  final DateTime openedAt;

  factory NotificationTapPayloadDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'NotificationTapPayload');
    final kind = NotificationKind.fromWireValue(
      ContractValue.nonEmptyString(json, 'kind', 'NotificationTapPayload'),
    );
    final targetType = NotificationTargetType.fromWireValue(
      ContractValue.nonEmptyString(
        json,
        'target_type',
        'NotificationTapPayload',
      ),
    );
    final reminderId = ContractValue.optionalString(
      json,
      'reminder_id',
      'NotificationTapPayload',
    );
    final recoveryBatchId = ContractValue.optionalString(
      json,
      'recovery_batch_id',
      'NotificationTapPayload',
    );
    final occurrenceKey = ContractValue.optionalString(
      json,
      'occurrence_key',
      'NotificationTapPayload',
    );
    if (kind == NotificationKind.reminder) {
      if (reminderId == null ||
          targetType == NotificationTargetType.reminderRecoveryBatch) {
        throw const FormatException(
          'Reminder tap payload identity is invalid.',
        );
      }
      if (targetType != NotificationTargetType.event && occurrenceKey != null) {
        throw const FormatException(
          'Only Event reminder taps can contain occurrence_key.',
        );
      }
    } else if (reminderId != null ||
        recoveryBatchId == null ||
        targetType != NotificationTargetType.reminderRecoveryBatch ||
        occurrenceKey != null) {
      throw const FormatException(
        'Recovery summary tap payload identity is invalid.',
      );
    }
    return NotificationTapPayloadDto(
      notificationId: ContractValue.nonEmptyString(
        json,
        'notification_id',
        'NotificationTapPayload',
      ),
      deliveryId: ContractValue.nonEmptyString(
        json,
        'delivery_id',
        'NotificationTapPayload',
      ),
      deliveryAttemptId: ContractValue.nonEmptyString(
        json,
        'delivery_attempt_id',
        'NotificationTapPayload',
      ),
      kind: kind,
      reminderId: reminderId,
      recoveryBatchId: recoveryBatchId,
      targetType: targetType,
      targetId: ContractValue.nonEmptyString(
        json,
        'target_id',
        'NotificationTapPayload',
      ),
      occurrenceKey: occurrenceKey,
      route: ContractValue.optionalString(
        json,
        'route',
        'NotificationTapPayload',
      ),
      openedAt: ContractValue.utcDateTime(
        json,
        'opened_at',
        'NotificationTapPayload',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'notification_id': notificationId,
    'delivery_id': deliveryId,
    'delivery_attempt_id': deliveryAttemptId,
    'kind': kind.wireValue,
    'reminder_id': reminderId,
    'recovery_batch_id': recoveryBatchId,
    'target_type': targetType.wireValue,
    'target_id': targetId,
    'occurrence_key': occurrenceKey,
    'route': route,
    'opened_at': ContractValue.formatUtcDateTime(
      openedAt,
      field: 'NotificationTapPayload.opened_at',
    ),
  };
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
    ContractValue.requireExactKeys(json, {
      'has_payload',
      'payload',
    }, 'NotificationTapPayloadResponse');
    final hasPayload = ContractValue.boolean(
      json,
      'has_payload',
      'NotificationTapPayloadResponse',
    );
    final rawPayload = json['payload'];
    if ((hasPayload && rawPayload is! Map<String, dynamic>) ||
        (!hasPayload && rawPayload != null)) {
      throw const FormatException(
        'NotificationTapPayloadResponse payload is inconsistent.',
      );
    }
    return NotificationTapPayloadResponseDto(
      hasPayload: hasPayload,
      payload: rawPayload is Map<String, dynamic>
          ? NotificationTapPayloadDto.fromJson(rawPayload)
          : null,
    );
  }
}

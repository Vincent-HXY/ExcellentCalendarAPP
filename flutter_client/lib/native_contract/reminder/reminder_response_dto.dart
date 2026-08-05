import '../shared/contract_value.dart';
import 'reminder_contract_enums.dart';

class ReminderResponseDto {
  const ReminderResponseDto({
    required this.reminderId,
    required this.targetType,
    required this.targetId,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required this.occurrenceStartAt,
    required this.remindAt,
    required this.methods,
    required this.isEnabled,
    required this.status,
    required this.reactivationCount,
    required this.createdAt,
    required this.updatedAt,
    this.advanceMinutes,
    this.message,
    this.scheduledAt,
    this.lastTriggeredAt,
    this.failureReason,
    this.lastCancellationReason,
    this.lastCancelledAt,
    this.expirationReason,
    this.expiredAt,
    this.reactivatedAt,
    this.deletedAt,
  });

  static const _keys = {
    'reminder_id',
    'target_type',
    'target_id',
    'recurrence_revision',
    'occurrence_key',
    'occurrence_start_at',
    'remind_at',
    'advance_minutes',
    'methods',
    'message',
    'is_enabled',
    'status',
    'scheduled_at',
    'last_triggered_at',
    'failure_reason',
    'last_cancellation_reason',
    'last_cancelled_at',
    'expiration_reason',
    'expired_at',
    'reactivated_at',
    'reactivation_count',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  final String reminderId;
  final ReminderTargetType targetType;
  final String targetId;
  final int? recurrenceRevision;
  final String? occurrenceKey;
  final DateTime? occurrenceStartAt;
  final DateTime remindAt;
  final List<ReminderMethod> methods;
  final int? advanceMinutes;
  final String? message;
  final bool isEnabled;
  final ReminderStatus status;
  final DateTime? scheduledAt;
  final DateTime? lastTriggeredAt;
  final String? failureReason;
  final ReminderCancellationReason? lastCancellationReason;
  final DateTime? lastCancelledAt;
  final ReminderExpirationReason? expirationReason;
  final DateTime? expiredAt;
  final DateTime? reactivatedAt;
  final int reactivationCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  String get id => reminderId;
  String? get cancellationReason => lastCancellationReason?.wireValue;

  bool get isRecurring => recurrenceRevision != null;

  factory ReminderResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'ReminderResponse');
    final methodValues = ContractValue.stringList(
      json,
      'methods',
      'ReminderResponse',
      allowed: ReminderMethod.values.map((value) => value.wireValue).toSet(),
      unique: true,
      nonEmpty: true,
    );
    final methods = List<ReminderMethod>.unmodifiable(
      methodValues.map(ReminderMethod.fromWireValue),
    );
    final status = ReminderStatus.fromWireValue(
      ContractValue.nonEmptyString(json, 'status', 'ReminderResponse'),
    );
    final recurrenceRevision = ContractValue.optionalInteger(
      json,
      'recurrence_revision',
      'ReminderResponse',
      minimum: 1,
    );
    final occurrenceKey = ContractValue.optionalString(
      json,
      'occurrence_key',
      'ReminderResponse',
    );
    final occurrenceStartAt = ContractValue.optionalUtcDateTime(
      json,
      'occurrence_start_at',
      'ReminderResponse',
      wholeSecond: true,
    );
    final advanceMinutes = ContractValue.optionalInteger(
      json,
      'advance_minutes',
      'ReminderResponse',
      minimum: 0,
    );
    final targetType = ReminderTargetType.fromWireValue(
      ContractValue.nonEmptyString(json, 'target_type', 'ReminderResponse'),
    );
    final recurringIdentity =
        recurrenceRevision != null &&
        occurrenceKey != null &&
        occurrenceStartAt != null;
    final ordinaryIdentity =
        recurrenceRevision == null &&
        occurrenceKey == null &&
        occurrenceStartAt == null;
    if (!(recurringIdentity || ordinaryIdentity) ||
        (recurringIdentity &&
            (targetType != ReminderTargetType.event ||
                advanceMinutes == null ||
                methods.length != 1 ||
                methods.single != ReminderMethod.popup))) {
      throw const FormatException(
        'ReminderResponse recurrence identity is invalid.',
      );
    }

    final isEnabled = ContractValue.boolean(
      json,
      'is_enabled',
      'ReminderResponse',
    );
    final rawExpirationReason = ContractValue.optionalString(
      json,
      'expiration_reason',
      'ReminderResponse',
    );
    final expirationReason = rawExpirationReason == null
        ? null
        : ReminderExpirationReason.fromWireValue(rawExpirationReason);
    final expiredAt = ContractValue.optionalUtcDateTime(
      json,
      'expired_at',
      'ReminderResponse',
    );
    if (status == ReminderStatus.expired) {
      if (isEnabled ||
          json['scheduled_at'] != null ||
          expirationReason != ReminderExpirationReason.recoveryWindowElapsed ||
          expiredAt == null) {
        throw const FormatException(
          'Expired ReminderResponse fields are inconsistent.',
        );
      }
    } else if (expirationReason != null || expiredAt != null) {
      throw const FormatException(
        'Non-expired ReminderResponse cannot contain expiration fields.',
      );
    }

    final rawCancellationReason = ContractValue.optionalString(
      json,
      'last_cancellation_reason',
      'ReminderResponse',
    );
    return ReminderResponseDto(
      reminderId: ContractValue.nonEmptyString(
        json,
        'reminder_id',
        'ReminderResponse',
      ),
      targetType: targetType,
      targetId: ContractValue.nonEmptyString(
        json,
        'target_id',
        'ReminderResponse',
      ),
      recurrenceRevision: recurrenceRevision,
      occurrenceKey: occurrenceKey,
      occurrenceStartAt: occurrenceStartAt,
      remindAt: ContractValue.utcDateTime(
        json,
        'remind_at',
        'ReminderResponse',
      ),
      methods: methods,
      advanceMinutes: advanceMinutes,
      message: ContractValue.optionalString(
        json,
        'message',
        'ReminderResponse',
      ),
      isEnabled: isEnabled,
      status: status,
      scheduledAt: ContractValue.optionalUtcDateTime(
        json,
        'scheduled_at',
        'ReminderResponse',
      ),
      lastTriggeredAt: ContractValue.optionalUtcDateTime(
        json,
        'last_triggered_at',
        'ReminderResponse',
      ),
      failureReason: ContractValue.optionalString(
        json,
        'failure_reason',
        'ReminderResponse',
      ),
      lastCancellationReason: rawCancellationReason == null
          ? null
          : ReminderCancellationReason.fromWireValue(rawCancellationReason),
      lastCancelledAt: ContractValue.optionalUtcDateTime(
        json,
        'last_cancelled_at',
        'ReminderResponse',
      ),
      expirationReason: expirationReason,
      expiredAt: expiredAt,
      reactivatedAt: ContractValue.optionalUtcDateTime(
        json,
        'reactivated_at',
        'ReminderResponse',
      ),
      reactivationCount: ContractValue.integer(
        json,
        'reactivation_count',
        'ReminderResponse',
        minimum: 0,
      ),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'ReminderResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'ReminderResponse',
      ),
      deletedAt: ContractValue.optionalUtcDateTime(
        json,
        'deleted_at',
        'ReminderResponse',
      ),
    );
  }
}

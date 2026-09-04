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
    required this.templateKey,
    required this.occurrenceDate,
    required this.advanceDays,
    required this.localTime,
    required this.timezoneMode,
    required this.fulfillmentDeliveryId,
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
    'template_key',
    'occurrence_date',
    'advance_days',
    'local_time',
    'timezone_mode',
    'fulfillment_delivery_id',
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
  final String? templateKey;
  final String? occurrenceDate;
  final int? advanceDays;
  final String? localTime;
  final String? timezoneMode;
  final String? fulfillmentDeliveryId;
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

  static final RegExp _localTimePattern = RegExp(
    r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$',
  );

  factory ReminderResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, _keys, 'ReminderResponse');
    final methodValues = ContractValue.stringList(
      json,
      'methods',
      'ReminderResponse',
      allowed: const {
        ReminderMethod.ring,
        ReminderMethod.popup,
      }.map((value) => value.wireValue).toSet(),
      unique: true,
      nonEmpty: true,
    );
    if (methodValues.length != 1) {
      throw const FormatException(
        'ReminderResponse.methods must contain exactly one supported method.',
      );
    }
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
    final occurrenceKey = ContractValue.optionalUuid(
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
    final templateKey = ContractValue.optionalUuid(
      json,
      'template_key',
      'ReminderResponse',
    );
    final occurrenceDate = ContractValue.optionalLocalDate(
      json,
      'occurrence_date',
      'ReminderResponse',
    );
    final advanceDays = ContractValue.optionalInteger(
      json,
      'advance_days',
      'ReminderResponse',
      minimum: 0,
      maximum: 365,
    );
    final localTime = ContractValue.optionalString(
      json,
      'local_time',
      'ReminderResponse',
    );
    if (localTime != null && !_localTimePattern.hasMatch(localTime)) {
      throw const FormatException(
        'ReminderResponse.local_time must use HH:mm.',
      );
    }
    final timezoneMode = ContractValue.optionalString(
      json,
      'timezone_mode',
      'ReminderResponse',
    );
    if (timezoneMode != null && timezoneMode != 'follow_device') {
      throw const FormatException('ReminderResponse.timezone_mode is invalid.');
    }
    final fulfillmentDeliveryId = ContractValue.optionalUuid(
      json,
      'fulfillment_delivery_id',
      'ReminderResponse',
    );

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
    final scheduledAt = ContractValue.optionalUtcDateTime(
      json,
      'scheduled_at',
      'ReminderResponse',
    );
    if (status == ReminderStatus.expired) {
      if (isEnabled ||
          scheduledAt != null ||
          expirationReason == null ||
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

    _validateTargetShape(
      targetType: targetType,
      recurrenceRevision: recurrenceRevision,
      occurrenceKey: occurrenceKey,
      occurrenceStartAt: occurrenceStartAt,
      templateKey: templateKey,
      occurrenceDate: occurrenceDate,
      advanceDays: advanceDays,
      localTime: localTime,
      timezoneMode: timezoneMode,
      fulfillmentDeliveryId: fulfillmentDeliveryId,
      advanceMinutes: advanceMinutes,
      methods: methods,
      status: status,
      expirationReason: expirationReason,
    );

    final rawCancellationReason = ContractValue.optionalString(
      json,
      'last_cancellation_reason',
      'ReminderResponse',
    );
    return ReminderResponseDto(
      reminderId: ContractValue.uuid(json, 'reminder_id', 'ReminderResponse'),
      targetType: targetType,
      targetId: ContractValue.uuid(json, 'target_id', 'ReminderResponse'),
      recurrenceRevision: recurrenceRevision,
      occurrenceKey: occurrenceKey,
      occurrenceStartAt: occurrenceStartAt,
      templateKey: templateKey,
      occurrenceDate: occurrenceDate,
      advanceDays: advanceDays,
      localTime: localTime,
      timezoneMode: timezoneMode,
      fulfillmentDeliveryId: fulfillmentDeliveryId,
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
      scheduledAt: scheduledAt,
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

  static void _validateTargetShape({
    required ReminderTargetType targetType,
    required int? recurrenceRevision,
    required String? occurrenceKey,
    required DateTime? occurrenceStartAt,
    required String? templateKey,
    required String? occurrenceDate,
    required int? advanceDays,
    required String? localTime,
    required String? timezoneMode,
    required String? fulfillmentDeliveryId,
    required int? advanceMinutes,
    required List<ReminderMethod> methods,
    required ReminderStatus status,
    required ReminderExpirationReason? expirationReason,
  }) {
    final method = methods.single;
    switch (targetType) {
      case ReminderTargetType.event:
        final recurringIdentity =
            recurrenceRevision != null &&
            occurrenceKey != null &&
            occurrenceStartAt != null;
        final ordinaryIdentity =
            recurrenceRevision == null &&
            occurrenceKey == null &&
            occurrenceStartAt == null;
        final hasTargetSpecificField =
            templateKey != null ||
            occurrenceDate != null ||
            advanceDays != null ||
            localTime != null ||
            timezoneMode != null ||
            fulfillmentDeliveryId != null;
        if (!(recurringIdentity || ordinaryIdentity) ||
            hasTargetSpecificField ||
            (expirationReason != null &&
                expirationReason !=
                    ReminderExpirationReason.recoveryWindowElapsed) ||
            (recurringIdentity &&
                (advanceMinutes == null || method != ReminderMethod.popup))) {
          throw const FormatException(
            'ReminderResponse Event target fields are inconsistent.',
          );
        }
        break;
      case ReminderTargetType.anniversary:
        final validShape =
            recurrenceRevision == null &&
            occurrenceKey != null &&
            occurrenceStartAt == null &&
            templateKey != null &&
            occurrenceDate != null &&
            advanceDays != null &&
            localTime != null &&
            timezoneMode == 'follow_device' &&
            advanceMinutes == null &&
            method == ReminderMethod.popup &&
            (expirationReason == null ||
                expirationReason ==
                    ReminderExpirationReason.anniversaryOccurrenceElapsed) &&
            ((status == ReminderStatus.sent) ==
                (fulfillmentDeliveryId != null));
        if (!validShape) {
          throw const FormatException(
            'ReminderResponse Anniversary target fields are inconsistent.',
          );
        }
        break;
      case ReminderTargetType.habit:
        final validShape =
            recurrenceRevision == null &&
            occurrenceKey != null &&
            occurrenceStartAt == null &&
            templateKey != null &&
            occurrenceDate != null &&
            advanceDays == null &&
            localTime != null &&
            timezoneMode == 'follow_device' &&
            fulfillmentDeliveryId == null &&
            advanceMinutes == null &&
            method == ReminderMethod.popup &&
            (expirationReason == null ||
                expirationReason ==
                    ReminderExpirationReason.habitOccurrenceElapsed);
        if (!validShape) {
          throw const FormatException(
            'ReminderResponse Habit target fields are inconsistent.',
          );
        }
        break;
    }
  }
}

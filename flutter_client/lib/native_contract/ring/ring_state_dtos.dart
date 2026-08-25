import '../common/native_error_dto.dart';
import '../notification/notification_contract_enums.dart';
import '../shared/contract_value.dart';
import 'ring_contract_enums.dart';
import 'ring_request_dtos.dart';

class RingSettingsDto {
  const RingSettingsDto({
    required this.revision,
    required this.ringtoneDisplayName,
    required this.ringtoneAvailable,
    required this.strongReminderEnabled,
  });

  final int revision;
  final String ringtoneDisplayName;
  final bool ringtoneAvailable;
  final bool strongReminderEnabled;

  factory RingSettingsDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'revision',
      'ringtone_display_name',
      'ringtone_available',
      'strong_reminder_enabled',
    }, 'RingSettings');
    return RingSettingsDto(
      revision: ContractValue.integer(
        json,
        'revision',
        'RingSettings',
        minimum: 0,
        maximum: 9007199254740991,
      ),
      ringtoneDisplayName: ContractValue.nonEmptyString(
        json,
        'ringtone_display_name',
        'RingSettings',
      ),
      ringtoneAvailable: ContractValue.boolean(
        json,
        'ringtone_available',
        'RingSettings',
      ),
      strongReminderEnabled: ContractValue.boolean(
        json,
        'strong_reminder_enabled',
        'RingSettings',
      ),
    );
  }
}

class RingCapabilitySnapshotDto {
  RingCapabilitySnapshotDto({
    required this.evaluatedAt,
    required this.sdkInt,
    required this.notificationPermission,
    required this.exactAlarmPermission,
    required this.fullScreenIntentPermission,
    required this.canPostNotifications,
    required this.canScheduleExactAlarms,
    required this.canUseFullScreenIntent,
    required this.ringChannelEnabled,
    required this.hasAudioOutput,
    required this.hasVibrator,
    required this.canEnableRing,
    required List<RingCapabilityBlockingReason> blockingReasons,
    required List<RingCapabilityDegradationReason> degradationReasons,
  }) : blockingReasons = List.unmodifiable(blockingReasons),
       degradationReasons = List.unmodifiable(degradationReasons);

  final DateTime evaluatedAt;
  final int sdkInt;
  final NotificationPermissionStatus notificationPermission;
  final ExactAlarmPermissionStatus exactAlarmPermission;
  final FullScreenIntentPermissionStatus fullScreenIntentPermission;
  final bool canPostNotifications;
  final bool canScheduleExactAlarms;
  final bool canUseFullScreenIntent;
  final bool ringChannelEnabled;
  final bool hasAudioOutput;
  final bool hasVibrator;
  final bool canEnableRing;
  final List<RingCapabilityBlockingReason> blockingReasons;
  final List<RingCapabilityDegradationReason> degradationReasons;

  factory RingCapabilitySnapshotDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'evaluated_at',
      'sdk_int',
      'notification_permission',
      'exact_alarm_permission',
      'full_screen_intent_permission',
      'can_post_notifications',
      'can_schedule_exact_alarms',
      'can_use_full_screen_intent',
      'ring_channel_enabled',
      'has_audio_output',
      'has_vibrator',
      'can_enable_ring',
      'blocking_reasons',
      'degradation_reasons',
    }, 'RingCapabilitySnapshot');
    final blockingReasons = _enumList(
      json,
      'blocking_reasons',
      'RingCapabilitySnapshot',
      RingCapabilityBlockingReason.fromWireValue,
    );
    final degradationReasons = _enumList(
      json,
      'degradation_reasons',
      'RingCapabilitySnapshot',
      RingCapabilityDegradationReason.fromWireValue,
    );
    final canEnableRing = ContractValue.boolean(
      json,
      'can_enable_ring',
      'RingCapabilitySnapshot',
    );
    final hasAudioOutput = ContractValue.boolean(
      json,
      'has_audio_output',
      'RingCapabilitySnapshot',
    );
    final hasVibrator = ContractValue.boolean(
      json,
      'has_vibrator',
      'RingCapabilitySnapshot',
    );
    if (canEnableRing != blockingReasons.isEmpty ||
        (canEnableRing && !hasAudioOutput && !hasVibrator)) {
      throw const FormatException(
        'RingCapabilitySnapshot capability invariants are invalid.',
      );
    }
    return RingCapabilitySnapshotDto(
      evaluatedAt: ContractValue.utcDateTime(
        json,
        'evaluated_at',
        'RingCapabilitySnapshot',
        wholeSecond: true,
      ),
      sdkInt: ContractValue.integer(
        json,
        'sdk_int',
        'RingCapabilitySnapshot',
        minimum: 1,
      ),
      notificationPermission: NotificationPermissionStatus.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'notification_permission',
          'RingCapabilitySnapshot',
        ),
      ),
      exactAlarmPermission: ExactAlarmPermissionStatus.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'exact_alarm_permission',
          'RingCapabilitySnapshot',
        ),
      ),
      fullScreenIntentPermission:
          FullScreenIntentPermissionStatus.fromWireValue(
            ContractValue.nonEmptyString(
              json,
              'full_screen_intent_permission',
              'RingCapabilitySnapshot',
            ),
          ),
      canPostNotifications: ContractValue.boolean(
        json,
        'can_post_notifications',
        'RingCapabilitySnapshot',
      ),
      canScheduleExactAlarms: ContractValue.boolean(
        json,
        'can_schedule_exact_alarms',
        'RingCapabilitySnapshot',
      ),
      canUseFullScreenIntent: ContractValue.boolean(
        json,
        'can_use_full_screen_intent',
        'RingCapabilitySnapshot',
      ),
      ringChannelEnabled: ContractValue.boolean(
        json,
        'ring_channel_enabled',
        'RingCapabilitySnapshot',
      ),
      hasAudioOutput: hasAudioOutput,
      hasVibrator: hasVibrator,
      canEnableRing: canEnableRing,
      blockingReasons: blockingReasons,
      degradationReasons: degradationReasons,
    );
  }
}

class ActiveRingItemDto {
  const ActiveRingItemDto({
    required this.notificationId,
    required this.deliveryId,
    required this.deliveryAttemptId,
    required this.reminderId,
    required this.eventId,
    required this.recoveryBatchId,
    required this.plannedAt,
    required this.addedAt,
  });

  final String notificationId;
  final String deliveryId;
  final String deliveryAttemptId;
  final String reminderId;
  final String eventId;
  final String? recoveryBatchId;
  final DateTime plannedAt;
  final DateTime addedAt;

  factory ActiveRingItemDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'notification_id',
      'delivery_id',
      'delivery_attempt_id',
      'reminder_id',
      'event_id',
      'recovery_batch_id',
      'planned_at',
      'added_at',
    }, 'ActiveRingItem');
    final notificationId = ContractValue.nonEmptyString(
      json,
      'notification_id',
      'ActiveRingItem',
    );
    final deliveryId = ContractValue.nonEmptyString(
      json,
      'delivery_id',
      'ActiveRingItem',
    );
    final deliveryAttemptId = ContractValue.nonEmptyString(
      json,
      'delivery_attempt_id',
      'ActiveRingItem',
    );
    final reminderId = ContractValue.nonEmptyString(
      json,
      'reminder_id',
      'ActiveRingItem',
    );
    final eventId = ContractValue.nonEmptyString(
      json,
      'event_id',
      'ActiveRingItem',
    );
    final recoveryBatchId = ContractValue.optionalString(
      json,
      'recovery_batch_id',
      'ActiveRingItem',
    );
    for (final entry in <String, String>{
      'notification_id': notificationId,
      'delivery_id': deliveryId,
      'delivery_attempt_id': deliveryAttemptId,
      'reminder_id': reminderId,
      'event_id': eventId,
    }.entries) {
      validateRingUuid(entry.value, 'ActiveRingItem.${entry.key}');
    }
    if (recoveryBatchId != null) {
      validateRingUuid(recoveryBatchId, 'ActiveRingItem.recovery_batch_id');
    }
    return ActiveRingItemDto(
      notificationId: notificationId,
      deliveryId: deliveryId,
      deliveryAttemptId: deliveryAttemptId,
      reminderId: reminderId,
      eventId: eventId,
      recoveryBatchId: recoveryBatchId,
      plannedAt: ContractValue.utcDateTime(
        json,
        'planned_at',
        'ActiveRingItem',
        wholeSecond: true,
      ),
      addedAt: ContractValue.utcDateTime(
        json,
        'added_at',
        'ActiveRingItem',
        wholeSecond: true,
      ),
    );
  }
}

class ActiveRingSessionDto {
  ActiveRingSessionDto({
    required this.sessionId,
    required this.revision,
    required this.phase,
    required this.generation,
    required this.startedAt,
    required this.phaseChangedAt,
    required this.audibleStartedAt,
    required this.audibleDeadlineAt,
    required this.quietSince,
    required this.controlNotificationVisible,
    required this.soundActive,
    required this.vibrationActive,
    required List<ActiveRingItemDto> items,
  }) : items = List.unmodifiable(items);

  final String sessionId;
  final int revision;
  final RingSessionPhase phase;
  final int generation;
  final DateTime startedAt;
  final DateTime phaseChangedAt;
  final DateTime? audibleStartedAt;
  final DateTime? audibleDeadlineAt;
  final DateTime? quietSince;
  final bool controlNotificationVisible;
  final bool soundActive;
  final bool vibrationActive;
  final List<ActiveRingItemDto> items;

  factory ActiveRingSessionDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'session_id',
      'revision',
      'phase',
      'generation',
      'started_at',
      'phase_changed_at',
      'audible_started_at',
      'audible_deadline_at',
      'quiet_since',
      'control_notification_visible',
      'sound_active',
      'vibration_active',
      'items',
    }, 'ActiveRingSession');
    final sessionId = ContractValue.nonEmptyString(
      json,
      'session_id',
      'ActiveRingSession',
    );
    validateRingUuid(sessionId, 'ActiveRingSession.session_id');
    final phase = RingSessionPhase.fromWireValue(
      ContractValue.nonEmptyString(json, 'phase', 'ActiveRingSession'),
    );
    final generation = ContractValue.integer(
      json,
      'generation',
      'ActiveRingSession',
      minimum: 0,
      maximum: 9007199254740991,
    );
    final audibleStartedAt = ContractValue.optionalUtcDateTime(
      json,
      'audible_started_at',
      'ActiveRingSession',
      wholeSecond: true,
    );
    final audibleDeadlineAt = ContractValue.optionalUtcDateTime(
      json,
      'audible_deadline_at',
      'ActiveRingSession',
      wholeSecond: true,
    );
    final quietSince = ContractValue.optionalUtcDateTime(
      json,
      'quiet_since',
      'ActiveRingSession',
      wholeSecond: true,
    );
    final controlNotificationVisible = ContractValue.boolean(
      json,
      'control_notification_visible',
      'ActiveRingSession',
    );
    final soundActive = ContractValue.boolean(
      json,
      'sound_active',
      'ActiveRingSession',
    );
    final vibrationActive = ContractValue.boolean(
      json,
      'vibration_active',
      'ActiveRingSession',
    );
    final rawItems = json['items'];
    if (rawItems is! List ||
        rawItems.isEmpty ||
        rawItems.any((item) => item is! Map<String, dynamic>)) {
      throw const FormatException(
        'ActiveRingSession.items must be a non-empty object array.',
      );
    }
    final items = rawItems
        .cast<Map<String, dynamic>>()
        .map(ActiveRingItemDto.fromJson)
        .toList(growable: false);
    if (items.map((item) => item.deliveryId).toSet().length != items.length ||
        items.map((item) => item.deliveryAttemptId).toSet().length !=
            items.length) {
      throw const FormatException(
        'ActiveRingSession item identities must be unique.',
      );
    }
    final phaseIsValid = switch (phase) {
      RingSessionPhase.prepared =>
        generation == 0 &&
            audibleStartedAt == null &&
            audibleDeadlineAt == null &&
            quietSince == null &&
            !soundActive &&
            !vibrationActive,
      RingSessionPhase.audible =>
        generation >= 1 &&
            audibleStartedAt != null &&
            audibleDeadlineAt != null &&
            quietSince == null &&
            controlNotificationVisible &&
            (soundActive || vibrationActive),
      RingSessionPhase.quietPending =>
        generation >= 1 &&
            audibleStartedAt != null &&
            audibleDeadlineAt != null &&
            quietSince != null &&
            controlNotificationVisible &&
            !soundActive &&
            !vibrationActive,
    };
    if (!phaseIsValid) {
      throw const FormatException('ActiveRingSession phase shape is invalid.');
    }
    return ActiveRingSessionDto(
      sessionId: sessionId,
      revision: ContractValue.integer(
        json,
        'revision',
        'ActiveRingSession',
        minimum: 1,
        maximum: 9007199254740991,
      ),
      phase: phase,
      generation: generation,
      startedAt: ContractValue.utcDateTime(
        json,
        'started_at',
        'ActiveRingSession',
        wholeSecond: true,
      ),
      phaseChangedAt: ContractValue.utcDateTime(
        json,
        'phase_changed_at',
        'ActiveRingSession',
        wholeSecond: true,
      ),
      audibleStartedAt: audibleStartedAt,
      audibleDeadlineAt: audibleDeadlineAt,
      quietSince: quietSince,
      controlNotificationVisible: controlNotificationVisible,
      soundActive: soundActive,
      vibrationActive: vibrationActive,
      items: items,
    );
  }
}

class RingStateSnapshotDto {
  const RingStateSnapshotDto({
    required this.capturedAt,
    required this.runtimeInstanceId,
    required this.sequence,
    required this.sessionRevision,
    required this.settings,
    required this.capability,
    required this.activeSession,
    required this.testState,
  });

  final DateTime capturedAt;
  final String runtimeInstanceId;
  final int sequence;
  final int sessionRevision;
  final RingSettingsDto settings;
  final RingCapabilitySnapshotDto capability;
  final ActiveRingSessionDto? activeSession;
  final RingTestState testState;

  factory RingStateSnapshotDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'captured_at',
      'runtime_instance_id',
      'sequence',
      'session_revision',
      'settings',
      'capability',
      'active_session',
      'test_state',
    }, 'RingStateSnapshot');
    final runtimeInstanceId = ContractValue.nonEmptyString(
      json,
      'runtime_instance_id',
      'RingStateSnapshot',
    );
    validateRingUuid(
      runtimeInstanceId,
      'RingStateSnapshot.runtime_instance_id',
    );
    final rawSettings = json['settings'];
    final rawCapability = json['capability'];
    final rawSession = json['active_session'];
    if (rawSettings is! Map<String, dynamic> ||
        rawCapability is! Map<String, dynamic> ||
        (rawSession != null && rawSession is! Map<String, dynamic>)) {
      throw const FormatException('RingStateSnapshot shape is invalid.');
    }
    final sessionRevision = ContractValue.integer(
      json,
      'session_revision',
      'RingStateSnapshot',
      minimum: 0,
      maximum: 9007199254740991,
    );
    final activeSession = rawSession == null
        ? null
        : ActiveRingSessionDto.fromJson(rawSession);
    final testState = RingTestState.fromWireValue(
      ContractValue.nonEmptyString(json, 'test_state', 'RingStateSnapshot'),
    );
    if ((activeSession != null && activeSession.revision != sessionRevision) ||
        (activeSession != null && testState != RingTestState.inactive)) {
      throw const FormatException(
        'RingStateSnapshot session projection is inconsistent.',
      );
    }
    return RingStateSnapshotDto(
      capturedAt: ContractValue.utcDateTime(
        json,
        'captured_at',
        'RingStateSnapshot',
        wholeSecond: true,
      ),
      runtimeInstanceId: runtimeInstanceId,
      sequence: ContractValue.integer(
        json,
        'sequence',
        'RingStateSnapshot',
        minimum: 0,
        maximum: 9007199254740991,
      ),
      sessionRevision: sessionRevision,
      settings: RingSettingsDto.fromJson(rawSettings),
      capability: RingCapabilitySnapshotDto.fromJson(rawCapability),
      activeSession: activeSession,
      testState: testState,
    );
  }
}

class RingStateChangedEventDto {
  const RingStateChangedEventDto({required this.reason, required this.state});

  final RingStateChangeReason reason;
  final RingStateSnapshotDto state;

  factory RingStateChangedEventDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'reason',
      'state',
    }, 'RingStateChangedEvent');
    final rawState = json['state'];
    if (rawState is! Map<String, dynamic>) {
      throw const FormatException(
        'RingStateChangedEvent.state must be object.',
      );
    }
    return RingStateChangedEventDto(
      reason: RingStateChangeReason.fromWireValue(
        ContractValue.nonEmptyString(json, 'reason', 'RingStateChangedEvent'),
      ),
      state: RingStateSnapshotDto.fromJson(rawState),
    );
  }
}

class PickRingtoneResponseDto {
  const PickRingtoneResponseDto({
    required this.selectionStatus,
    required this.state,
  });

  final RingRingtoneSelectionStatus selectionStatus;
  final RingStateSnapshotDto state;

  factory PickRingtoneResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'selection_status',
      'state',
    }, 'PickRingtoneResponse');
    final rawState = json['state'];
    if (rawState is! Map<String, dynamic>) {
      throw const FormatException('PickRingtoneResponse.state must be object.');
    }
    return PickRingtoneResponseDto(
      selectionStatus: RingRingtoneSelectionStatus.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'selection_status',
          'PickRingtoneResponse',
        ),
      ),
      state: RingStateSnapshotDto.fromJson(rawState),
    );
  }
}

class RingSnoozeItemResultDto {
  const RingSnoozeItemResultDto({
    required this.deliveryId,
    required this.status,
    required this.snoozedReminderId,
    required this.error,
  });

  final String deliveryId;
  final RingItemActionStatus status;
  final String? snoozedReminderId;
  final NativeErrorDto? error;

  factory RingSnoozeItemResultDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'delivery_id',
      'status',
      'snoozed_reminder_id',
      'error',
    }, 'RingSnoozeItemResult');
    final deliveryId = ContractValue.nonEmptyString(
      json,
      'delivery_id',
      'RingSnoozeItemResult',
    );
    validateRingUuid(deliveryId, 'RingSnoozeItemResult.delivery_id');
    final status = RingItemActionStatus.fromWireValue(
      ContractValue.nonEmptyString(json, 'status', 'RingSnoozeItemResult'),
    );
    final snoozedReminderId = ContractValue.optionalString(
      json,
      'snoozed_reminder_id',
      'RingSnoozeItemResult',
    );
    final rawError = json['error'];
    if (rawError != null && rawError is! Map<String, dynamic>) {
      throw const FormatException(
        'RingSnoozeItemResult.error must be object or null.',
      );
    }
    final error = rawError == null ? null : NativeErrorDto.fromJson(rawError);
    if (status == RingItemActionStatus.succeeded) {
      if (snoozedReminderId == null || error != null) {
        throw const FormatException(
          'Successful RingSnoozeItemResult shape is invalid.',
        );
      }
      validateRingUuid(
        snoozedReminderId,
        'RingSnoozeItemResult.snoozed_reminder_id',
      );
    } else if (snoozedReminderId != null || error == null) {
      throw const FormatException(
        'Failed RingSnoozeItemResult shape is invalid.',
      );
    }
    return RingSnoozeItemResultDto(
      deliveryId: deliveryId,
      status: status,
      snoozedReminderId: snoozedReminderId,
      error: error,
    );
  }
}

class RingSnoozeActiveResponseDto {
  RingSnoozeActiveResponseDto({
    required List<RingSnoozeItemResultDto> results,
    required this.succeededCount,
    required this.failedCount,
    required this.state,
  }) : results = List.unmodifiable(results);

  final List<RingSnoozeItemResultDto> results;
  final int succeededCount;
  final int failedCount;
  final RingStateSnapshotDto state;

  factory RingSnoozeActiveResponseDto.fromJson(
    Map<String, dynamic> json, {
    List<String>? requestedDeliveryIds,
  }) {
    ContractValue.requireExactKeys(json, {
      'results',
      'succeeded_count',
      'failed_count',
      'state',
    }, 'RingSnoozeActiveResponse');
    final rawResults = json['results'];
    final rawState = json['state'];
    if (rawResults is! List ||
        rawResults.isEmpty ||
        rawResults.any((item) => item is! Map<String, dynamic>) ||
        rawState is! Map<String, dynamic>) {
      throw const FormatException('RingSnoozeActiveResponse shape is invalid.');
    }
    final results = rawResults
        .cast<Map<String, dynamic>>()
        .map(RingSnoozeItemResultDto.fromJson)
        .toList(growable: false);
    final succeededCount = ContractValue.integer(
      json,
      'succeeded_count',
      'RingSnoozeActiveResponse',
      minimum: 0,
      maximum: 9007199254740991,
    );
    final failedCount = ContractValue.integer(
      json,
      'failed_count',
      'RingSnoozeActiveResponse',
      minimum: 0,
      maximum: 9007199254740991,
    );
    if (succeededCount + failedCount != results.length ||
        succeededCount !=
            results
                .where((item) => item.status == RingItemActionStatus.succeeded)
                .length ||
        (requestedDeliveryIds != null &&
            !_sameOrder(
              results.map((item) => item.deliveryId).toList(growable: false),
              requestedDeliveryIds,
            ))) {
      throw const FormatException(
        'RingSnoozeActiveResponse result invariants are invalid.',
      );
    }
    final state = RingStateSnapshotDto.fromJson(rawState);
    final remainingIds =
        state.activeSession?.items.map((item) => item.deliveryId).toSet() ??
        const <String>{};
    for (final result in results) {
      final shouldRemain = result.status == RingItemActionStatus.failed;
      if (remainingIds.contains(result.deliveryId) != shouldRemain) {
        throw const FormatException(
          'RingSnoozeActiveResponse state does not match item results.',
        );
      }
    }
    return RingSnoozeActiveResponseDto(
      results: results,
      succeededCount: succeededCount,
      failedCount: failedCount,
      state: state,
    );
  }
}

List<T> _enumList<T>(
  Map<String, dynamic> json,
  String key,
  String parent,
  T Function(String value) parse,
) {
  final values = ContractValue.stringList(json, key, parent, unique: true);
  return List<T>.unmodifiable(values.map(parse));
}

bool _sameOrder(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

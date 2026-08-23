import 'ring_contract_enums.dart';

const _maxSafeInteger = 9007199254740991;
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

void validateRingUuid(String value, String field) {
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('$field must be a UUID.');
  }
}

void validateRingRevision(int value, String field, {int minimum = 0}) {
  if (value < minimum || value > _maxSafeInteger) {
    throw FormatException('$field must be an integer in range.');
  }
}

class PickRingtoneRequestDto {
  const PickRingtoneRequestDto({required this.expectedSettingsRevision});

  final int expectedSettingsRevision;

  Map<String, dynamic> toJson() {
    validateRingRevision(
      expectedSettingsRevision,
      'PickRingtoneRequest.expected_settings_revision',
    );
    return {'expected_settings_revision': expectedSettingsRevision};
  }
}

class UpdateRingSettingsRequestDto {
  const UpdateRingSettingsRequestDto({
    required this.expectedSettingsRevision,
    required this.strongReminderEnabled,
  });

  final int expectedSettingsRevision;
  final bool strongReminderEnabled;

  Map<String, dynamic> toJson() {
    validateRingRevision(
      expectedSettingsRevision,
      'UpdateRingSettingsRequest.expected_settings_revision',
    );
    return {
      'expected_settings_revision': expectedSettingsRevision,
      'strong_reminder_enabled': strongReminderEnabled,
    };
  }
}

class RingTestRequestDto {
  const RingTestRequestDto({
    required this.action,
    required this.expectedSettingsRevision,
  });

  final RingTestAction action;
  final int expectedSettingsRevision;

  Map<String, dynamic> toJson() {
    validateRingRevision(
      expectedSettingsRevision,
      'RingTestRequest.expected_settings_revision',
    );
    return {
      'action': action.wireValue,
      'expected_settings_revision': expectedSettingsRevision,
    };
  }
}

class ActiveRingItemsRequestDto {
  ActiveRingItemsRequestDto({
    required this.runtimeInstanceId,
    required this.sessionId,
    required this.expectedSessionRevision,
    required List<String> deliveryIds,
  }) : deliveryIds = List.unmodifiable(deliveryIds);

  final String runtimeInstanceId;
  final String sessionId;
  final int expectedSessionRevision;
  final List<String> deliveryIds;

  Map<String, dynamic> toJson() {
    validateRingUuid(
      runtimeInstanceId,
      'ActiveRingItemsRequest.runtime_instance_id',
    );
    validateRingUuid(sessionId, 'ActiveRingItemsRequest.session_id');
    validateRingRevision(
      expectedSessionRevision,
      'ActiveRingItemsRequest.expected_session_revision',
      minimum: 1,
    );
    if (deliveryIds.isEmpty ||
        deliveryIds.toSet().length != deliveryIds.length) {
      throw const FormatException(
        'ActiveRingItemsRequest.delivery_ids must be non-empty and unique.',
      );
    }
    for (final id in deliveryIds) {
      validateRingUuid(id, 'ActiveRingItemsRequest.delivery_ids');
    }
    return {
      'runtime_instance_id': runtimeInstanceId,
      'session_id': sessionId,
      'expected_session_revision': expectedSessionRevision,
      'delivery_ids': deliveryIds,
    };
  }
}

class CompleteRingItemRequestDto {
  const CompleteRingItemRequestDto({
    required this.runtimeInstanceId,
    required this.sessionId,
    required this.expectedSessionRevision,
    required this.deliveryId,
  });

  final String runtimeInstanceId;
  final String sessionId;
  final int expectedSessionRevision;
  final String deliveryId;

  Map<String, dynamic> toJson() {
    validateRingUuid(
      runtimeInstanceId,
      'CompleteRingItemRequest.runtime_instance_id',
    );
    validateRingUuid(sessionId, 'CompleteRingItemRequest.session_id');
    validateRingRevision(
      expectedSessionRevision,
      'CompleteRingItemRequest.expected_session_revision',
      minimum: 1,
    );
    validateRingUuid(deliveryId, 'CompleteRingItemRequest.delivery_id');
    return {
      'runtime_instance_id': runtimeInstanceId,
      'session_id': sessionId,
      'expected_session_revision': expectedSessionRevision,
      'delivery_id': deliveryId,
    };
  }
}

import '../../native_contract/reminder/create_reminder_request_dto.dart';
import '../../native_contract/reminder/reminder_contract_enums.dart';

class CreateReminderCommand {
  const CreateReminderCommand({
    required this.requestId,
    required this.targetType,
    required this.targetId,
    required this.methods,
    required this.isEnabled,
    required this.source,
    this.remindAt,
    this.advanceMinutes,
    this.message,
  });

  // Application-local correlation only. The current request schema does not
  // declare request_id, so this value is intentionally not sent to native.
  final String requestId;
  final ReminderTargetType targetType;
  final String targetId;
  final DateTime? remindAt;
  final int? advanceMinutes;
  final Set<ReminderMethod> methods;
  final String? message;
  final bool isEnabled;
  final ReminderSource source;

  String? validate() {
    if (requestId.trim().isEmpty) {
      return 'requestId must not be empty.';
    }
    if (targetId.trim().isEmpty) {
      return 'targetId must not be empty.';
    }
    if (methods.isEmpty) {
      return 'methods must not be empty.';
    }
    if (remindAt == null && advanceMinutes == null) {
      return 'remindAt or advanceMinutes must be provided.';
    }
    if (advanceMinutes != null && advanceMinutes! < 0) {
      return 'advanceMinutes must be non-negative.';
    }
    return null;
  }

  CreateReminderRequestDto toRequestDto() {
    return CreateReminderRequestDto(
      targetType: targetType,
      targetId: targetId,
      remindAt: remindAt,
      advanceMinutes: advanceMinutes,
      methods: methods.toList(growable: false),
      message: message,
      isEnabled: isEnabled,
      source: source,
    );
  }
}

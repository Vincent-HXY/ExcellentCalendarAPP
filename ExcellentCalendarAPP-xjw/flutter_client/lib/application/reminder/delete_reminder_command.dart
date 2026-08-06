import '../../native_contract/reminder/cancel_reminder_request_dto.dart';

class DeleteReminderCommand {
  const DeleteReminderCommand({
    required this.reminderId,
    required this.requestId,
    this.reason,
  });

  final String reminderId;

  // Application-local correlation only. The current request schema does not
  // declare request_id, so this value is intentionally not sent to native.
  final String requestId;
  final String? reason;

  String? validate() {
    if (reminderId.trim().isEmpty) {
      return 'reminderId must not be empty.';
    }
    if (requestId.trim().isEmpty) {
      return 'requestId must not be empty.';
    }
    return null;
  }

  CancelReminderRequestDto toRequestDto() {
    return CancelReminderRequestDto(id: reminderId, reason: reason);
  }
}

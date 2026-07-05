import '../native_contract/reminder/cancel_reminder_request_dto.dart';
import '../native_contract/reminder/create_reminder_request_dto.dart';
import '../native_contract/reminder/reminder_response_dto.dart';
import '../native_contract/reminder/schedule_pending_reminders_dto.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class ReminderNativeGateway {
  Future<NativeInvocation<ReminderResponseDto>> createReminder(
    CreateReminderRequestDto request,
  );

  Future<NativeInvocation<ReminderResponseDto>> cancelReminder(
    CancelReminderRequestDto request,
  );

  Future<NativeInvocation<SchedulePendingRemindersResponseDto>> schedulePending(
    SchedulePendingRemindersRequestDto request,
  );
}

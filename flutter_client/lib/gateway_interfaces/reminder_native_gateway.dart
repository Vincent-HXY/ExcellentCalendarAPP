import '../native_contract/reminder/cancel_reminder_request_dto.dart';
import '../native_contract/reminder/create_reminder_request_dto.dart';
import '../native_contract/reminder/list_reminders_request_dto.dart';
import '../native_contract/reminder/reminder_list_response_dto.dart';
import '../native_contract/reminder/reminder_response_dto.dart';
import '../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../native_contract/reminder/update_reminder_request_dto.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class ReminderNativeGateway {
  Future<NativeInvocation<ReminderResponseDto>> createReminder(
    CreateReminderRequestDto request,
  );

  Future<NativeInvocation<ReminderResponseDto>> cancelReminder(
    CancelReminderRequestDto request,
  );

  Future<NativeInvocation<ReminderResponseDto>> updateReminder(
    UpdateReminderRequestDto request,
  );

  Future<NativeInvocation<ReminderListResponseDto>> listReminders(
    ListRemindersRequestDto request,
  );

  Future<NativeInvocation<ReconcileReminderScheduleResponseDto>>
  reconcileSchedule(ReconcileReminderScheduleRequestDto request);
}

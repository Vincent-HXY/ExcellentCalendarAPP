import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_contract_enums.dart';
import 'package:excellent_calendar/native_contract/notification/notification_initialize_response_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_permission_status_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:excellent_calendar/native_contract/notification/request_notification_permission_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/schedule_pending_reminders_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

NativeInvocation<T> successInvocation<T>(
  T data, {
  Map<String, dynamic>? rawData,
  String requestId = 'request-1',
}) {
  return NativeInvocation<T>(
    rawResponse: {
      'ok': true,
      'data': rawData ?? const {},
      'error': null,
      'contract_version': 1,
      'request_id': requestId,
    },
    result: NativeResultDto<T>(
      ok: true,
      data: data,
      error: null,
      contractVersion: 1,
      requestId: requestId,
    ),
    isNativeResult: true,
  );
}

NativeInvocation<T> failureInvocation<T>({
  String code = 'NATIVE_INTERNAL_ERROR',
  String message = 'Native failure.',
  bool isNativeResult = true,
}) {
  return NativeInvocation<T>(
    rawResponse: {
      'ok': false,
      'data': null,
      'error': {
        'code': code,
        'message': message,
        'details': null,
        'retryable': false,
      },
      'contract_version': 1,
      'request_id': 'request-failure',
    },
    result: NativeResultDto<T>(
      ok: false,
      data: null,
      error: NativeErrorDto(code: code, message: message),
      contractVersion: 1,
      requestId: 'request-failure',
    ),
    isNativeResult: isNativeResult,
  );
}

const initializedResponse = NotificationInitializeResponseDto(
  initialized: true,
  notificationChannelReady: true,
  defaultChannelId: 'excellent_calendar_reminders',
  sdkInt: 35,
);

NotificationPermissionStatusDto permissionStatus({
  required bool canPost,
  required bool canScheduleExact,
}) {
  return NotificationPermissionStatusDto(
    notificationPermission: canPost
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied,
    exactAlarmPermission: canScheduleExact
        ? ExactAlarmPermissionStatus.granted
        : ExactAlarmPermissionStatus.denied,
    canPostNotifications: canPost,
    canScheduleExactAlarms: canScheduleExact,
    sdkInt: 35,
    shouldShowNotificationRationale: !canPost,
  );
}

RequestNotificationPermissionResponseDto permissionRequestResponse({
  required bool canPost,
  required bool canScheduleExact,
  bool shouldOpenSettings = false,
}) {
  return RequestNotificationPermissionResponseDto(
    notificationPermission: canPost
        ? NotificationPermissionStatus.granted
        : NotificationPermissionStatus.denied,
    exactAlarmPermission: canScheduleExact
        ? ExactAlarmPermissionStatus.granted
        : ExactAlarmPermissionStatus.denied,
    canPostNotifications: canPost,
    canScheduleExactAlarms: canScheduleExact,
    shouldOpenSettings: shouldOpenSettings,
  );
}

const scheduleResponse = SchedulePendingRemindersResponseDto(
  scheduledCount: 1,
  skippedCount: 0,
  failedCount: 0,
  unsupportedMethodCount: 0,
  hasMore: false,
  failedReminderIds: [],
  unsupportedReminderIds: [],
);

const reconcileResponse = ReconcileReminderScheduleResponseDto(
  action: 'scheduled',
  nextRemindAt: null,
  processedDueCount: 0,
  failedCount: 0,
  continuationEnqueued: false,
  failedReminderIds: [],
);

NotificationTapPayloadDto tapPayload({
  String notificationId = 'notification-1',
  String? reminderId = 'reminder-1',
  NotificationTargetType targetType = NotificationTargetType.event,
  String targetId = 'event-1',
}) {
  return NotificationTapPayloadDto(
    notificationId: notificationId,
    reminderId: reminderId,
    targetType: targetType,
    targetId: targetId,
    route: null,
    openedAt: DateTime.utc(2026, 7, 5, 10),
  );
}

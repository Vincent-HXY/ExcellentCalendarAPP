import '../../application/reminder/reconcile_reminder_schedule_use_case.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';

class ReminderScheduleLifecycleResult {
  const ReminderScheduleLifecycleResult.skipped()
    : response = null,
      errorMessage = null;

  const ReminderScheduleLifecycleResult.success(this.response)
    : errorMessage = null;

  const ReminderScheduleLifecycleResult.failure(this.errorMessage)
    : response = null;

  final ReconcileReminderScheduleResponseDto? response;
  final String? errorMessage;

  bool get failed => errorMessage != null;
}

class ReminderScheduleLifecycleCoordinator {
  const ReminderScheduleLifecycleCoordinator(this._reconcileUseCase);

  final ReconcileReminderScheduleUseCase _reconcileUseCase;

  Future<ReminderScheduleLifecycleResult> reconcileIfAllowed({
    required NotificationPermissionStatusDto? permissionStatus,
    required ReminderScheduleTrigger triggerSource,
    bool force = false,
  }) async {
    if (permissionStatus == null ||
        !permissionStatus.canPostNotifications ||
        !permissionStatus.canScheduleExactAlarms) {
      return const ReminderScheduleLifecycleResult.skipped();
    }
    try {
      final invocation = await _reconcileUseCase.execute(
        triggerSource: triggerSource,
        force: force,
      );
      if (!invocation.result.ok || invocation.result.data == null) {
        return ReminderScheduleLifecycleResult.failure(
          invocation.result.error?.message ??
              'Native notification operation failed.',
        );
      }
      return ReminderScheduleLifecycleResult.success(invocation.result.data!);
    } catch (_) {
      return const ReminderScheduleLifecycleResult.failure(
        'Native notification operation failed.',
      );
    }
  }
}

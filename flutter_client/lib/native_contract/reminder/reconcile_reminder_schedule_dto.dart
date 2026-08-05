import '../shared/contract_json_object.dart';
import '../shared/contract_value.dart';

enum ReminderScheduleTrigger {
  appStart('app_start'),
  appResume('app_resume'),
  mutation('mutation'),
  bootCompleted('boot_completed'),
  packageReplaced('package_replaced'),
  timeChanged('time_changed'),
  timezoneChanged('timezone_changed'),
  periodicWorker('periodic_worker'),
  alarmFired('alarm_fired'),
  manualRetry('manual_retry');

  const ReminderScheduleTrigger(this.wireValue);
  final String wireValue;
}

class ReconcileReminderScheduleRequestDto {
  const ReconcileReminderScheduleRequestDto({
    required this.triggerSource,
    this.force = false,
  });

  final ReminderScheduleTrigger triggerSource;
  final bool force;

  Map<String, dynamic> toJson() => {
    'trigger_source': triggerSource.wireValue,
    'force': force,
  };
}

class ReconcileReminderScheduleResponseDto {
  const ReconcileReminderScheduleResponseDto({
    required this.action,
    required this.nextRemindAt,
    required this.processedDueCount,
    required this.failedCount,
    required this.continuationEnqueued,
    required this.failedReminderIds,
  });

  final String action;
  final DateTime? nextRemindAt;
  final int processedDueCount;
  final int failedCount;
  final bool continuationEnqueued;
  final List<String> failedReminderIds;

  factory ReconcileReminderScheduleResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    const keys = {
      'action',
      'next_remind_at',
      'processed_due_count',
      'failed_count',
      'continuation_enqueued',
      'failed_reminder_ids',
    };
    ContractJsonObject.rejectUnknownKeys(
      json,
      keys,
      'ReconcileReminderScheduleResponse',
    );
    ContractJsonObject.requireKeys(
      json,
      keys,
      'ReconcileReminderScheduleResponse',
    );
    final action = json['action'];
    if (action is! String ||
        !{'scheduled', 'cancelled', 'unchanged'}.contains(action)) {
      throw const FormatException('action is invalid.');
    }
    final rawNext = json['next_remind_at'];
    final processed = json['processed_due_count'];
    final failed = json['failed_count'];
    final continuation = json['continuation_enqueued'];
    final rawIds = json['failed_reminder_ids'];
    if (rawNext != null && rawNext is! String) {
      throw const FormatException('next_remind_at must be string or null.');
    }
    if (processed is! int || processed < 0 || failed is! int || failed < 0) {
      throw const FormatException(
        'reconcile counts must be non-negative integers.',
      );
    }
    if (continuation is! bool ||
        rawIds is! List ||
        rawIds.any((id) => id is! String || id.isEmpty)) {
      throw const FormatException(
        'reconcile continuation or failure ids are invalid.',
      );
    }
    final ids = rawIds.cast<String>();
    if (ids.toSet().length != ids.length || ids.length != failed) {
      throw const FormatException(
        'failed_count must match unique failed_reminder_ids.',
      );
    }
    return ReconcileReminderScheduleResponseDto(
      action: action,
      nextRemindAt: rawNext == null
          ? null
          : ContractValue.parseUtcDateTime(
              rawNext,
              field: 'ReconcileReminderScheduleResponse.next_remind_at',
            ),
      processedDueCount: processed,
      failedCount: failed,
      continuationEnqueued: continuation,
      failedReminderIds: List.unmodifiable(ids),
    );
  }
}

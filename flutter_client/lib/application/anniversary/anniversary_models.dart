enum AnniversaryCalendarType { solar, lunar }

enum AnniversaryKind { anniversary, countdown, birthday, holiday }

enum CountdownRelation { remaining, elapsed, today, unavailable }

enum AnniversaryImportance {
  unimportantNotUrgent,
  importantNotUrgent,
  unimportantUrgent,
  importantUrgent,
}

enum AnniversaryReminderOffset {
  sameDay(0),
  oneDayBefore(1),
  sevenDaysBefore(7);

  const AnniversaryReminderOffset(this.advanceDays);

  final int advanceDays;
}

enum AnniversaryReminderMethod { popup }

class AnniversaryReminderLocalTime {
  const AnniversaryReminderLocalTime(this.hour, this.minute)
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  static const nineAm = AnniversaryReminderLocalTime(9, 0);

  final int hour;
  final int minute;

  String get wireValue =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  factory AnniversaryReminderLocalTime.parse(String value) {
    final match = RegExp(
      r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$',
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('Reminder local time must be HH:mm.');
    }
    return AnniversaryReminderLocalTime(
      int.parse(value.substring(0, 2)),
      int.parse(value.substring(3, 5)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AnniversaryReminderLocalTime &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}

DateTime anniversaryDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

class AnniversaryRecord {
  AnniversaryRecord({
    required this.id,
    required this.title,
    required DateTime date,
    required this.calendarType,
    required this.categoryId,
    required this.recurrenceId,
    required this.note,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  }) : date = anniversaryDateOnly(date);

  final String id;
  final String title;
  final DateTime date;
  final AnniversaryCalendarType calendarType;
  final String? categoryId;
  final String? recurrenceId;
  final String? note;
  final AnniversaryImportance importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class AnniversaryDraft {
  AnniversaryDraft({
    required this.title,
    required DateTime date,
    required this.calendarType,
    required this.categoryId,
    required this.note,
    required this.importance,
  }) : date = anniversaryDateOnly(date);

  final String title;
  final DateTime date;
  final AnniversaryCalendarType calendarType;
  final String? categoryId;
  final String? note;
  final AnniversaryImportance importance;
}

class RecurrenceDraft {
  const RecurrenceDraft.yearly() : frequency = 'yearly', interval = 1;

  final String frequency;
  final int interval;
}

class ReminderDraft {
  const ReminderDraft({
    required this.advanceDays,
    this.localTime = AnniversaryReminderLocalTime.nineAm,
    this.method = AnniversaryReminderMethod.popup,
    this.isEnabled = true,
    this.templateKey,
  });

  final int advanceDays;
  final AnniversaryReminderLocalTime localTime;
  final AnniversaryReminderMethod method;
  final bool isEnabled;
  final String? templateKey;

  String get identityTuple =>
      '$advanceDays|${localTime.wireValue}|${method.name}';

  ReminderDraft copyWith({
    int? advanceDays,
    AnniversaryReminderLocalTime? localTime,
    AnniversaryReminderMethod? method,
    bool? isEnabled,
  }) => ReminderDraft(
    advanceDays: advanceDays ?? this.advanceDays,
    localTime: localTime ?? this.localTime,
    method: method ?? this.method,
    isEnabled: isEnabled ?? this.isEnabled,
    templateKey: templateKey,
  );
}

class CreateAnniversaryPlan {
  CreateAnniversaryPlan({
    required this.anniversary,
    required this.kind,
    required this.recurrence,
    required List<ReminderDraft> reminders,
    this.remindersEnabled = false,
  }) : reminders = List.unmodifiable(reminders);

  final AnniversaryDraft anniversary;
  final AnniversaryKind kind;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;
  final bool remindersEnabled;
}

class UpdateAnniversaryPlan {
  UpdateAnniversaryPlan({
    required this.id,
    required this.expectedUpdatedAt,
    required this.anniversary,
    required this.kind,
    required this.recurrence,
    required List<ReminderDraft> reminders,
    this.remindersEnabled = false,
  }) : reminders = List.unmodifiable(reminders);

  final String id;
  final DateTime expectedUpdatedAt;
  final AnniversaryDraft anniversary;
  final AnniversaryKind kind;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;
  final bool remindersEnabled;
}

class AnniversaryListQuery {
  const AnniversaryListQuery({this.page = 1, this.pageSize = 20});

  final int page;
  final int pageSize;
}

class AnniversaryListResult {
  AnniversaryListResult({
    required List<AnniversaryListItem> items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<AnniversaryListItem> items;
  final int? total;
  final int page;
  final int pageSize;
  final bool hasMore;
}

class CountdownSnapshot {
  CountdownSnapshot({
    required this.relation,
    required this.days,
    required DateTime? targetOccurrenceDate,
    required this.dateLabel,
    required this.weekdayLabel,
  }) : targetOccurrenceDate = targetOccurrenceDate == null
           ? null
           : anniversaryDateOnly(targetOccurrenceDate);

  final CountdownRelation relation;
  final int? days;
  final DateTime? targetOccurrenceDate;
  final String dateLabel;
  final String weekdayLabel;
}

class AnniversaryListItem {
  const AnniversaryListItem({
    required this.anniversary,
    required this.kind,
    required this.countdown,
    required this.iconKey,
  });

  final AnniversaryRecord anniversary;
  final AnniversaryKind kind;
  final CountdownSnapshot countdown;
  final String iconKey;
}

class AnniversaryDetail {
  AnniversaryDetail({
    required this.anniversary,
    required this.kind,
    required this.countdown,
    required this.iconKey,
    required this.recurrence,
    required List<ReminderDraft> reminders,
    this.remindersEnabled = false,
    this.activeReminderCount = 0,
    this.scheduleReconciliationRequired = false,
    this.scheduleCapability = const AnniversaryScheduleCapability.notRequired(),
  }) : reminders = List.unmodifiable(reminders);

  final AnniversaryRecord anniversary;
  final AnniversaryKind kind;
  final CountdownSnapshot countdown;
  final String iconKey;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;
  final bool remindersEnabled;
  final int activeReminderCount;
  final bool scheduleReconciliationRequired;
  final AnniversaryScheduleCapability scheduleCapability;

  AnniversaryListItem toListItem() {
    return AnniversaryListItem(
      anniversary: anniversary,
      kind: kind,
      countdown: countdown,
      iconKey: iconKey,
    );
  }
}

enum AnniversaryScheduleStatus {
  notRequired,
  scheduledExact,
  scheduledApproximate,
  pendingPermission,
  pendingReconciliation,
}

enum AnniversaryNotificationPermissionStatus {
  granted,
  denied,
  notRequired,
  permanentlyDenied,
  unknown,
}

enum AnniversaryExactAlarmPermissionStatus {
  granted,
  denied,
  notRequired,
  unknown,
}

enum AnniversaryScheduleDegradationReason {
  notificationPermissionUnavailable,
  exactAlarmPermissionUnavailable,
  schedulerRetryRequired,
}

class AnniversaryScheduleCapability {
  const AnniversaryScheduleCapability({
    required this.status,
    required this.scheduleReconciliationRequired,
    required this.notificationPermissionStatus,
    required this.exactAlarmPermissionStatus,
    required this.degradationReasons,
  });

  const AnniversaryScheduleCapability.notRequired()
    : status = AnniversaryScheduleStatus.notRequired,
      scheduleReconciliationRequired = false,
      notificationPermissionStatus =
          AnniversaryNotificationPermissionStatus.notRequired,
      exactAlarmPermissionStatus =
          AnniversaryExactAlarmPermissionStatus.notRequired,
      degradationReasons = const [];

  final AnniversaryScheduleStatus status;
  final bool scheduleReconciliationRequired;
  final AnniversaryNotificationPermissionStatus notificationPermissionStatus;
  final AnniversaryExactAlarmPermissionStatus exactAlarmPermissionStatus;
  final List<AnniversaryScheduleDegradationReason> degradationReasons;

  bool get needsNotificationSettings =>
      notificationPermissionStatus ==
          AnniversaryNotificationPermissionStatus.denied ||
      notificationPermissionStatus ==
          AnniversaryNotificationPermissionStatus.permanentlyDenied;

  bool get exactAlarmDegraded =>
      status == AnniversaryScheduleStatus.scheduledApproximate ||
      degradationReasons.contains(
        AnniversaryScheduleDegradationReason.exactAlarmPermissionUnavailable,
      );

  String? get warningMessage {
    if (needsNotificationSettings) {
      return '纪念日已保存，但通知权限未开启；授权后会自动恢复提醒。';
    }
    if (scheduleReconciliationRequired) {
      return '纪念日已保存，提醒调度将在稍后自动恢复。';
    }
    if (exactAlarmDegraded) {
      return '纪念日已保存；当前提醒可能稍有延迟。';
    }
    return null;
  }
}

class AnniversarySharePayload {
  const AnniversarySharePayload({
    required this.title,
    required this.countdownText,
    required this.targetDate,
  });

  final String title;
  final String countdownText;
  final DateTime? targetDate;
}

enum AnniversaryFailureCode {
  titleEmpty,
  dateInvalid,
  calendarUnsupported,
  notFound,
  updateConflict,
  reminderConfigInvalid,
  reminderDuplicate,
  reminderLimitExceeded,
  occurrenceQueryInvalid,
  occurrenceCursorInvalid,
  occurrenceCursorExpired,
  contractValidation,
  nativeInternal,
  unknown,
}

class AnniversaryGatewayException implements Exception {
  const AnniversaryGatewayException(
    this.code, {
    this.retryable = false,
    this.debugMessage,
  });

  final AnniversaryFailureCode code;
  final bool retryable;
  final String? debugMessage;
}

String anniversaryFailureMessage(Object error) {
  if (error is! AnniversaryGatewayException) {
    return '操作失败，请稍后重试';
  }
  return switch (error.code) {
    AnniversaryFailureCode.titleEmpty => '请输入纪念日名称',
    AnniversaryFailureCode.dateInvalid => '请选择有效的纪念日日期',
    AnniversaryFailureCode.calendarUnsupported => '当前版本暂不支持农历',
    AnniversaryFailureCode.notFound => '该纪念日不存在或已删除',
    AnniversaryFailureCode.updateConflict => '纪念日已在其他页面被修改，请返回详情刷新后重试',
    AnniversaryFailureCode.reminderConfigInvalid => '提醒设置不正确，请检查后重试',
    AnniversaryFailureCode.reminderDuplicate => '不能添加相同时间的重复提醒',
    AnniversaryFailureCode.reminderLimitExceeded => '每个纪念日最多设置 5 条提醒',
    AnniversaryFailureCode.occurrenceQueryInvalid => '纪念日查询范围或筛选条件不正确',
    AnniversaryFailureCode.occurrenceCursorInvalid => '纪念日分页数据格式不正确',
    AnniversaryFailureCode.occurrenceCursorExpired => '纪念日列表已更新，请重新加载',
    AnniversaryFailureCode.contractValidation => '纪念日数据格式不正确，请稍后重试',
    AnniversaryFailureCode.nativeInternal => '纪念日服务暂时不可用，请稍后重试',
    AnniversaryFailureCode.unknown => '操作失败，请稍后重试',
  };
}

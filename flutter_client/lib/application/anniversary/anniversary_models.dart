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
    this.methods = const ['popup'],
  });

  final int advanceDays;
  final List<String> methods;
}

class CreateAnniversaryPlan {
  CreateAnniversaryPlan({
    required this.anniversary,
    required this.kind,
    required this.recurrence,
    required List<ReminderDraft> reminders,
  }) : reminders = List.unmodifiable(reminders);

  final AnniversaryDraft anniversary;
  final AnniversaryKind kind;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;
}

class UpdateAnniversaryPlan {
  UpdateAnniversaryPlan({
    required this.id,
    required this.anniversary,
    required this.kind,
    required this.recurrence,
    required List<ReminderDraft> reminders,
  }) : reminders = List.unmodifiable(reminders);

  final String id;
  final AnniversaryDraft anniversary;
  final AnniversaryKind kind;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;
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
  }) : reminders = List.unmodifiable(reminders);

  final AnniversaryRecord anniversary;
  final AnniversaryKind kind;
  final CountdownSnapshot countdown;
  final String iconKey;
  final RecurrenceDraft? recurrence;
  final List<ReminderDraft> reminders;

  AnniversaryListItem toListItem() {
    return AnniversaryListItem(
      anniversary: anniversary,
      kind: kind,
      countdown: countdown,
      iconKey: iconKey,
    );
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
    AnniversaryFailureCode.contractValidation => '纪念日数据格式不正确，请稍后重试',
    AnniversaryFailureCode.nativeInternal => '纪念日服务暂时不可用，请稍后重试',
    AnniversaryFailureCode.unknown => '操作失败，请稍后重试',
  };
}

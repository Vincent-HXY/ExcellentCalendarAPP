import '../common/pagination_response_dto.dart';
import '../shared/contract_value.dart';
import '../shared/civil_date.dart';
import 'habit_contract_enums.dart';
import 'habit_contract_value.dart';

class HabitResponseDto {
  const HabitResponseDto({
    required this.id,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.recurrenceId,
    required this.targetCountHundredths,
    required this.unit,
    required this.startDate,
    required this.endDate,
    required this.endedDate,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String title;
  final String? description;
  final String? categoryId;
  final String recurrenceId;
  final int? targetCountHundredths;
  final String? unit;
  final String startDate;
  final String endDate;
  final String? endedDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get isQuantitative => targetCountHundredths != null;

  factory HabitResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitResponse';
    ContractValue.requireExactKeys(json, const {
      'id',
      'title',
      'description',
      'category_id',
      'recurrence_id',
      'target_count_hundredths',
      'unit',
      'start_date',
      'end_date',
      'ended_date',
      'is_active',
      'created_at',
      'updated_at',
      'deleted_at',
    }, parent);
    final target = ContractValue.optionalInteger(
      json,
      'target_count_hundredths',
      parent,
      minimum: 1,
      maximum: HabitContractValue.maxSafeInteger,
    );
    final unit = HabitContractValue.optionalLimitedString(
      json,
      'unit',
      parent,
      maximumCodePoints: 32,
    );
    if ((target == null) != (unit == null) || (unit?.isEmpty ?? false)) {
      throw const FormatException('Habit target projection is inconsistent.');
    }
    final active = ContractValue.boolean(json, 'is_active', parent);
    final ended = ContractValue.optionalLocalDate(json, 'ended_date', parent);
    final deleted = ContractValue.optionalUtcDateTime(
      json,
      'deleted_at',
      parent,
      wholeSecond: true,
    );
    if ((active && ended != null) ||
        (!active && deleted == null && ended == null)) {
      throw const FormatException('Habit lifecycle facts are inconsistent.');
    }
    return HabitResponseDto(
      id: ContractValue.uuid(json, 'id', parent),
      title: HabitContractValue.limitedString(
        json,
        'title',
        parent,
        maximumCodePoints: 80,
      ),
      description: HabitContractValue.optionalLimitedString(
        json,
        'description',
        parent,
        maximumCodePoints: 2000,
      ),
      categoryId: ContractValue.optionalString(json, 'category_id', parent),
      recurrenceId: ContractValue.uuid(json, 'recurrence_id', parent),
      targetCountHundredths: target,
      unit: unit,
      startDate: ContractValue.localDate(json, 'start_date', parent),
      endDate: ContractValue.localDate(json, 'end_date', parent),
      endedDate: ended,
      isActive: active,
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        parent,
        wholeSecond: true,
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        parent,
        wholeSecond: true,
      ),
      deletedAt: deleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category_id': categoryId,
    'recurrence_id': recurrenceId,
    'target_count_hundredths': targetCountHundredths,
    'unit': unit,
    'start_date': startDate,
    'end_date': endDate,
    'ended_date': endedDate,
    'is_active': isActive,
    'created_at': HabitContractValue.utcSecond(createdAt, 'created_at'),
    'updated_at': HabitContractValue.utcSecond(updatedAt, 'updated_at'),
    'deleted_at': deletedAt == null
        ? null
        : HabitContractValue.utcSecond(deletedAt!, 'deleted_at'),
  };
}

class HabitRecurrenceResponseDto {
  const HabitRecurrenceResponseDto({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory HabitRecurrenceResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitRecurrenceResponse';
    ContractValue.requireExactKeys(json, const {
      'id',
      'frequency',
      'interval',
      'timezone_mode',
      'created_at',
      'updated_at',
      'deleted_at',
    }, parent);
    if (json['frequency'] != 'daily' ||
        json['interval'] != 1 ||
        json['timezone_mode'] != 'follow_device' ||
        json['deleted_at'] != null) {
      throw const FormatException('Habit recurrence projection is invalid.');
    }
    return HabitRecurrenceResponseDto(
      id: ContractValue.uuid(json, 'id', parent),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        parent,
        wholeSecond: true,
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        parent,
        wholeSecond: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'frequency': 'daily',
    'interval': 1,
    'timezone_mode': 'follow_device',
    'created_at': HabitContractValue.utcSecond(createdAt, 'created_at'),
    'updated_at': HabitContractValue.utcSecond(updatedAt, 'updated_at'),
    'deleted_at': null,
  };
}

class HabitCheckInResponseDto {
  const HabitCheckInResponseDto({
    required this.id,
    required this.habitId,
    required this.checkDate,
    required this.status,
    required this.completedCountHundredths,
    required this.targetCountSnapshotHundredths,
    required this.unitSnapshot,
    required this.completedAt,
    required this.note,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String habitId;
  final String checkDate;
  final HabitCheckInStatusContract status;
  final int? completedCountHundredths;
  final int? targetCountSnapshotHundredths;
  final String? unitSnapshot;
  final DateTime? completedAt;
  final String? note;
  final HabitCheckInSourceContract source;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory HabitCheckInResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitCheckInResponse';
    ContractValue.requireExactKeys(json, const {
      'id',
      'habit_id',
      'check_date',
      'status',
      'completed_count_hundredths',
      'target_count_snapshot_hundredths',
      'unit_snapshot',
      'completed_at',
      'note',
      'source',
      'created_at',
      'updated_at',
      'deleted_at',
    }, parent);
    if (json['deleted_at'] != null) {
      throw const FormatException('Active check-in cannot be deleted.');
    }
    final status = HabitCheckInStatusContract.fromWireValue(
      ContractValue.nonEmptyString(json, 'status', parent),
    );
    final completed = ContractValue.optionalInteger(
      json,
      'completed_count_hundredths',
      parent,
      minimum: 1,
      maximum: HabitContractValue.maxSafeInteger,
    );
    final target = ContractValue.optionalInteger(
      json,
      'target_count_snapshot_hundredths',
      parent,
      minimum: 1,
      maximum: HabitContractValue.maxSafeInteger,
    );
    final unit = HabitContractValue.optionalLimitedString(
      json,
      'unit_snapshot',
      parent,
      maximumCodePoints: 32,
    );
    final completedAt = ContractValue.optionalUtcDateTime(
      json,
      'completed_at',
      parent,
      wholeSecond: true,
    );
    final quantityShape =
        (status == HabitCheckInStatusContract.done ||
            status == HabitCheckInStatusContract.partial) &&
        completed != null &&
        target != null &&
        unit != null &&
        completedAt != null;
    final binaryShape =
        status == HabitCheckInStatusContract.done &&
        completed == null &&
        target == null &&
        unit == null &&
        completedAt != null;
    final skippedShape =
        status == HabitCheckInStatusContract.skipped &&
        completed == null &&
        target == null &&
        unit == null &&
        completedAt == null;
    if (!(skippedShape || binaryShape || quantityShape)) {
      throw const FormatException('Habit check-in fact shape is invalid.');
    }
    return HabitCheckInResponseDto(
      id: ContractValue.uuid(json, 'id', parent),
      habitId: ContractValue.uuid(json, 'habit_id', parent),
      checkDate: ContractValue.localDate(json, 'check_date', parent),
      status: status,
      completedCountHundredths: completed,
      targetCountSnapshotHundredths: target,
      unitSnapshot: unit,
      completedAt: completedAt,
      note: HabitContractValue.optionalLimitedString(
        json,
        'note',
        parent,
        maximumCodePoints: 500,
      ),
      source: HabitCheckInSourceContract.fromWireValue(
        ContractValue.nonEmptyString(json, 'source', parent),
      ),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        parent,
        wholeSecond: true,
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        parent,
        wholeSecond: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'habit_id': habitId,
    'check_date': checkDate,
    'status': status.wireValue,
    'completed_count_hundredths': completedCountHundredths,
    'target_count_snapshot_hundredths': targetCountSnapshotHundredths,
    'unit_snapshot': unitSnapshot,
    'completed_at': completedAt == null
        ? null
        : HabitContractValue.utcSecond(completedAt!, 'completed_at'),
    'note': note,
    'source': source.wireValue,
    'created_at': HabitContractValue.utcSecond(createdAt, 'created_at'),
    'updated_at': HabitContractValue.utcSecond(updatedAt, 'updated_at'),
    'deleted_at': null,
  };
}

class HabitDailyStatusResponseDto {
  const HabitDailyStatusResponseDto({
    required this.date,
    required this.status,
    required this.isFinal,
    required this.checkIn,
    required this.completionRatio,
  });
  final String date;
  final HabitDailyStatusContract status;
  final bool isFinal;
  final HabitCheckInResponseDto? checkIn;
  final double? completionRatio;

  factory HabitDailyStatusResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitDailyStatusResponse';
    ContractValue.requireExactKeys(json, const {
      'date',
      'status',
      'is_final',
      'check_in',
      'completion_ratio',
    }, parent);
    final status = HabitDailyStatusContract.fromWireValue(
      ContractValue.nonEmptyString(json, 'status', parent),
    );
    final rawCheckIn = json['check_in'];
    final checkIn = rawCheckIn == null
        ? null
        : HabitCheckInResponseDto.fromJson(
            HabitContractValue.object(rawCheckIn, '$parent.check_in'),
          );
    final rawRatio = json['completion_ratio'];
    final ratio = rawRatio == null
        ? null
        : HabitContractValue.ratio(json, 'completion_ratio', parent);
    final isFinal = ContractValue.boolean(json, 'is_final', parent);
    final projected = switch (status) {
      HabitDailyStatusContract.upcoming || HabitDailyStatusContract.absent =>
        checkIn == null && ratio == null && !isFinal,
      HabitDailyStatusContract.missed =>
        checkIn == null && ratio == null && isFinal,
      HabitDailyStatusContract.skipped =>
        checkIn?.status == HabitCheckInStatusContract.skipped &&
            ratio == null &&
            isFinal,
      HabitDailyStatusContract.partial =>
        checkIn?.status == HabitCheckInStatusContract.partial &&
            ratio != null &&
            ratio > 0 &&
            ratio < 1,
      HabitDailyStatusContract.done =>
        checkIn?.status == HabitCheckInStatusContract.done &&
            ratio == 1 &&
            isFinal,
    };
    if (!projected) {
      throw const FormatException('Habit daily projection is inconsistent.');
    }
    return HabitDailyStatusResponseDto(
      date: ContractValue.localDate(json, 'date', parent),
      status: status,
      isFinal: isFinal,
      checkIn: checkIn,
      completionRatio: ratio,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'status': status.wireValue,
    'is_final': isFinal,
    'check_in': checkIn?.toJson(),
    'completion_ratio': completionRatio,
  };
}

class HabitStatisticsResponseDto {
  const HabitStatisticsResponseDto({
    required this.asOfDate,
    required this.elapsedEligibleDays,
    required this.doneDays,
    required this.skippedDays,
    required this.partialDays,
    required this.missedDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.completionRate7Days,
    required this.completionRate30Days,
    required this.completionRateAll,
    required this.quantityProgressRate7Days,
    required this.quantityProgressRate30Days,
    required this.quantityProgressRateAll,
    required this.totalCompletedCountHundredths,
    required this.averageCompletedCountPerEligibleDayHundredths,
  });
  final String asOfDate;
  final int elapsedEligibleDays;
  final int doneDays;
  final int skippedDays;
  final int partialDays;
  final int missedDays;
  final int currentStreak;
  final int longestStreak;
  final double completionRate7Days;
  final double completionRate30Days;
  final double completionRateAll;
  final double? quantityProgressRate7Days;
  final double? quantityProgressRate30Days;
  final double? quantityProgressRateAll;
  final int? totalCompletedCountHundredths;
  final int? averageCompletedCountPerEligibleDayHundredths;
  bool get isQuantitative => quantityProgressRateAll != null;

  factory HabitStatisticsResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitStatisticsResponse';
    ContractValue.requireExactKeys(json, const {
      'as_of_date',
      'elapsed_eligible_days',
      'done_days',
      'skipped_days',
      'partial_days',
      'missed_days',
      'current_streak',
      'longest_streak',
      'completion_rate_7_days',
      'completion_rate_30_days',
      'completion_rate_all',
      'quantity_progress_rate_7_days',
      'quantity_progress_rate_30_days',
      'quantity_progress_rate_all',
      'total_completed_count_hundredths',
      'average_completed_count_per_eligible_day_hundredths',
    }, parent);
    double? optionalRatio(String key) =>
        json[key] == null ? null : HabitContractValue.ratio(json, key, parent);
    final q7 = optionalRatio('quantity_progress_rate_7_days');
    final q30 = optionalRatio('quantity_progress_rate_30_days');
    final qAll = optionalRatio('quantity_progress_rate_all');
    final total = ContractValue.optionalInteger(
      json,
      'total_completed_count_hundredths',
      parent,
      minimum: 0,
      maximum: HabitContractValue.maxSafeInteger,
    );
    final average = ContractValue.optionalInteger(
      json,
      'average_completed_count_per_eligible_day_hundredths',
      parent,
      minimum: 0,
      maximum: HabitContractValue.maxSafeInteger,
    );
    if ({
          q7 == null,
          q30 == null,
          qAll == null,
          total == null,
          average == null,
        }.length !=
        1) {
      throw const FormatException(
        'Habit quantity statistics are inconsistent.',
      );
    }
    return HabitStatisticsResponseDto(
      asOfDate: ContractValue.localDate(json, 'as_of_date', parent),
      elapsedEligibleDays: ContractValue.integer(
        json,
        'elapsed_eligible_days',
        parent,
        minimum: 0,
      ),
      doneDays: ContractValue.integer(json, 'done_days', parent, minimum: 0),
      skippedDays: ContractValue.integer(
        json,
        'skipped_days',
        parent,
        minimum: 0,
      ),
      partialDays: ContractValue.integer(
        json,
        'partial_days',
        parent,
        minimum: 0,
      ),
      missedDays: ContractValue.integer(
        json,
        'missed_days',
        parent,
        minimum: 0,
      ),
      currentStreak: ContractValue.integer(
        json,
        'current_streak',
        parent,
        minimum: 0,
      ),
      longestStreak: ContractValue.integer(
        json,
        'longest_streak',
        parent,
        minimum: 0,
      ),
      completionRate7Days: HabitContractValue.ratio(
        json,
        'completion_rate_7_days',
        parent,
      ),
      completionRate30Days: HabitContractValue.ratio(
        json,
        'completion_rate_30_days',
        parent,
      ),
      completionRateAll: HabitContractValue.ratio(
        json,
        'completion_rate_all',
        parent,
      ),
      quantityProgressRate7Days: q7,
      quantityProgressRate30Days: q30,
      quantityProgressRateAll: qAll,
      totalCompletedCountHundredths: total,
      averageCompletedCountPerEligibleDayHundredths: average,
    );
  }

  Map<String, dynamic> toJson() => {
    'as_of_date': asOfDate,
    'elapsed_eligible_days': elapsedEligibleDays,
    'done_days': doneDays,
    'skipped_days': skippedDays,
    'partial_days': partialDays,
    'missed_days': missedDays,
    'current_streak': currentStreak,
    'longest_streak': longestStreak,
    'completion_rate_7_days': completionRate7Days,
    'completion_rate_30_days': completionRate30Days,
    'completion_rate_all': completionRateAll,
    'quantity_progress_rate_7_days': quantityProgressRate7Days,
    'quantity_progress_rate_30_days': quantityProgressRate30Days,
    'quantity_progress_rate_all': quantityProgressRateAll,
    'total_completed_count_hundredths': totalCompletedCountHundredths,
    'average_completed_count_per_eligible_day_hundredths':
        averageCompletedCountPerEligibleDayHundredths,
  };
}

class HabitReminderTemplateResponseDto {
  const HabitReminderTemplateResponseDto({
    required this.templateKey,
    required this.habitId,
    required this.localTime,
    required this.isEnabled,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });
  final String templateKey;
  final String habitId;
  final String localTime;
  final bool isEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory HabitReminderTemplateResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitReminderTemplateResponse';
    ContractValue.requireExactKeys(json, const {
      'template_key',
      'habit_id',
      'local_time',
      'timezone_mode',
      'method',
      'is_enabled',
      'created_at',
      'updated_at',
      'deleted_at',
    }, parent);
    if (json['timezone_mode'] != 'follow_device' || json['method'] != 'popup') {
      throw const FormatException('Habit reminder template constants differ.');
    }
    return HabitReminderTemplateResponseDto(
      templateKey: ContractValue.uuid(json, 'template_key', parent),
      habitId: ContractValue.uuid(json, 'habit_id', parent),
      localTime: HabitContractValue.localTime(json, 'local_time', parent),
      isEnabled: ContractValue.boolean(json, 'is_enabled', parent),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        parent,
        wholeSecond: true,
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        parent,
        wholeSecond: true,
      ),
      deletedAt: ContractValue.optionalUtcDateTime(
        json,
        'deleted_at',
        parent,
        wholeSecond: true,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'template_key': templateKey,
    'habit_id': habitId,
    'local_time': localTime,
    'timezone_mode': 'follow_device',
    'method': 'popup',
    'is_enabled': isEnabled,
    'created_at': HabitContractValue.utcSecond(createdAt, 'created_at'),
    'updated_at': HabitContractValue.utcSecond(updatedAt, 'updated_at'),
    'deleted_at': deletedAt == null
        ? null
        : HabitContractValue.utcSecond(deletedAt!, 'deleted_at'),
  };
}

class HabitReminderSettingsResponseDto {
  const HabitReminderSettingsResponseDto({
    required this.isEnabled,
    required this.template,
    required this.activeReminderCount,
    required this.scheduleReconciliationRequired,
  });
  final bool isEnabled;
  final HabitReminderTemplateResponseDto? template;
  final int activeReminderCount;
  final bool scheduleReconciliationRequired;

  factory HabitReminderSettingsResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitReminderSettingsResponse';
    ContractValue.requireExactKeys(json, const {
      'is_enabled',
      'template',
      'active_reminder_count',
      'schedule_reconciliation_required',
    }, parent);
    final enabled = ContractValue.boolean(json, 'is_enabled', parent);
    final rawTemplate = json['template'];
    final template = rawTemplate == null
        ? null
        : HabitReminderTemplateResponseDto.fromJson(
            HabitContractValue.object(rawTemplate, '$parent.template'),
          );
    final count = ContractValue.integer(
      json,
      'active_reminder_count',
      parent,
      minimum: 0,
      maximum: 1,
    );
    if ((enabled &&
            (template == null ||
                !template.isEnabled ||
                template.deletedAt != null)) ||
        (!enabled && count != 0) ||
        (!enabled &&
            template != null &&
            (template.isEnabled || template.deletedAt != null))) {
      throw const FormatException('Habit reminder settings are inconsistent.');
    }
    return HabitReminderSettingsResponseDto(
      isEnabled: enabled,
      template: template,
      activeReminderCount: count,
      scheduleReconciliationRequired: ContractValue.boolean(
        json,
        'schedule_reconciliation_required',
        parent,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'is_enabled': isEnabled,
    'template': template?.toJson(),
    'active_reminder_count': activeReminderCount,
    'schedule_reconciliation_required': scheduleReconciliationRequired,
  };
}

class HabitScheduleCapabilityResponseDto {
  HabitScheduleCapabilityResponseDto({
    required this.scheduleStatus,
    required this.scheduleReconciliationRequired,
    required this.notificationPermissionStatus,
    required this.exactAlarmPermissionStatus,
    required List<HabitScheduleDegradationReasonContract> degradationReasons,
  }) : degradationReasons = List.unmodifiable(degradationReasons);
  final HabitScheduleStatusContract scheduleStatus;
  final bool scheduleReconciliationRequired;
  final HabitNotificationPermissionContract notificationPermissionStatus;
  final HabitExactAlarmPermissionContract exactAlarmPermissionStatus;
  final List<HabitScheduleDegradationReasonContract> degradationReasons;

  factory HabitScheduleCapabilityResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    const parent = 'HabitScheduleCapabilityResponse';
    ContractValue.requireExactKeys(json, const {
      'schedule_status',
      'schedule_reconciliation_required',
      'notification_permission_status',
      'exact_alarm_permission_status',
      'degradation_reasons',
    }, parent);
    final status = HabitScheduleStatusContract.fromWireValue(
      ContractValue.nonEmptyString(json, 'schedule_status', parent),
    );
    final reconciliation = ContractValue.boolean(
      json,
      'schedule_reconciliation_required',
      parent,
    );
    final mustReconcile =
        status == HabitScheduleStatusContract.pendingPermission ||
        status == HabitScheduleStatusContract.pendingReconciliation;
    if (mustReconcile != reconciliation) {
      throw const FormatException('Habit schedule status is inconsistent.');
    }
    final reasons = ContractValue.stringList(
      json,
      'degradation_reasons',
      parent,
      unique: true,
    ).map(HabitScheduleDegradationReasonContract.fromWireValue).toList();
    return HabitScheduleCapabilityResponseDto(
      scheduleStatus: status,
      scheduleReconciliationRequired: reconciliation,
      notificationPermissionStatus:
          HabitNotificationPermissionContract.fromWireValue(
            ContractValue.nonEmptyString(
              json,
              'notification_permission_status',
              parent,
            ),
          ),
      exactAlarmPermissionStatus:
          HabitExactAlarmPermissionContract.fromWireValue(
            ContractValue.nonEmptyString(
              json,
              'exact_alarm_permission_status',
              parent,
            ),
          ),
      degradationReasons: reasons,
    );
  }

  Map<String, dynamic> toJson() => {
    'schedule_status': scheduleStatus.wireValue,
    'schedule_reconciliation_required': scheduleReconciliationRequired,
    'notification_permission_status': notificationPermissionStatus.wireValue,
    'exact_alarm_permission_status': exactAlarmPermissionStatus.wireValue,
    'degradation_reasons': degradationReasons
        .map((item) => item.wireValue)
        .toList(),
  };
}

class HabitTodayProgressResponseDto {
  const HabitTodayProgressResponseDto({
    required this.asOfDate,
    required this.activeCount,
    required this.doneCount,
    required this.eligibleCount,
    required this.skippedCount,
    required this.partialCount,
    required this.absentCount,
  });
  final String asOfDate;
  final int activeCount;
  final int doneCount;
  final int eligibleCount;
  final int skippedCount;
  final int partialCount;
  final int absentCount;

  factory HabitTodayProgressResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitTodayProgressResponse';
    ContractValue.requireExactKeys(json, const {
      'as_of_date',
      'active_count',
      'done_count',
      'eligible_count',
      'skipped_count',
      'partial_count',
      'absent_count',
    }, parent);
    int count(String key) => ContractValue.integer(
      json,
      key,
      parent,
      minimum: 0,
      maximum: HabitContractValue.maxSafeInteger,
    );
    final active = count('active_count');
    final done = count('done_count');
    final eligible = count('eligible_count');
    final skipped = count('skipped_count');
    final partial = count('partial_count');
    final absent = count('absent_count');
    if (active != eligible + skipped || eligible != done + partial + absent) {
      throw const FormatException('Habit today progress sum is inconsistent.');
    }
    return HabitTodayProgressResponseDto(
      asOfDate: ContractValue.localDate(json, 'as_of_date', parent),
      activeCount: active,
      doneCount: done,
      eligibleCount: eligible,
      skippedCount: skipped,
      partialCount: partial,
      absentCount: absent,
    );
  }

  Map<String, dynamic> toJson() => {
    'as_of_date': asOfDate,
    'active_count': activeCount,
    'done_count': doneCount,
    'eligible_count': eligibleCount,
    'skipped_count': skippedCount,
    'partial_count': partialCount,
    'absent_count': absentCount,
  };
}

class HabitSummaryResponseDto {
  const HabitSummaryResponseDto({
    required this.habit,
    required this.lifecycleStatus,
    required this.today,
    required this.statistics,
    required this.reminderSettings,
    required this.challengeTimeProgress,
    required this.remainingDays,
  });
  final HabitResponseDto habit;
  final HabitLifecycleStatusContract lifecycleStatus;
  final HabitDailyStatusResponseDto? today;
  final HabitStatisticsResponseDto statistics;
  final HabitReminderSettingsResponseDto reminderSettings;
  final double challengeTimeProgress;
  final int remainingDays;

  factory HabitSummaryResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitSummaryResponse';
    ContractValue.requireExactKeys(json, const {
      'habit',
      'lifecycle_status',
      'today',
      'statistics',
      'reminder_settings',
      'challenge_time_progress',
      'remaining_days',
    }, parent);
    final lifecycle = HabitLifecycleStatusContract.fromWireValue(
      ContractValue.nonEmptyString(json, 'lifecycle_status', parent),
    );
    final rawToday = json['today'];
    final today = rawToday == null
        ? null
        : HabitDailyStatusResponseDto.fromJson(
            HabitContractValue.object(rawToday, '$parent.today'),
          );
    if ((lifecycle == HabitLifecycleStatusContract.upcoming && today != null) ||
        (lifecycle == HabitLifecycleStatusContract.active && today == null)) {
      throw const FormatException('Habit summary today projection is invalid.');
    }
    return HabitSummaryResponseDto(
      habit: HabitResponseDto.fromJson(
        HabitContractValue.object(json['habit'], '$parent.habit'),
      ),
      lifecycleStatus: lifecycle,
      today: today,
      statistics: HabitStatisticsResponseDto.fromJson(
        HabitContractValue.object(json['statistics'], '$parent.statistics'),
      ),
      reminderSettings: HabitReminderSettingsResponseDto.fromJson(
        HabitContractValue.object(
          json['reminder_settings'],
          '$parent.reminder_settings',
        ),
      ),
      challengeTimeProgress: HabitContractValue.ratio(
        json,
        'challenge_time_progress',
        parent,
      ),
      remainingDays: ContractValue.integer(
        json,
        'remaining_days',
        parent,
        minimum: 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'habit': habit.toJson(),
    'lifecycle_status': lifecycleStatus.wireValue,
    'today': today?.toJson(),
    'statistics': statistics.toJson(),
    'reminder_settings': reminderSettings.toJson(),
    'challenge_time_progress': challengeTimeProgress,
    'remaining_days': remainingDays,
  };
}

class HabitListResponseDto {
  HabitListResponseDto({
    required List<HabitSummaryResponseDto> items,
    required this.pagination,
    required this.todayProgress,
  }) : items = List.unmodifiable(items);
  final List<HabitSummaryResponseDto> items;
  final PaginationResponseDto pagination;
  final HabitTodayProgressResponseDto todayProgress;

  factory HabitListResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitListResponse';
    ContractValue.requireExactKeys(json, const {
      'items',
      'pagination',
      'today_progress',
    }, parent);
    final items = HabitContractValue.objectList(
      json['items'],
      '$parent.items',
      maximum: 100,
    ).map(HabitSummaryResponseDto.fromJson).toList();
    final pagination = PaginationResponseDto.fromJson(
      HabitContractValue.object(json['pagination'], '$parent.pagination'),
    );
    if (pagination.pageSize > 100 ||
        (pagination.nextCursor?.isEmpty ?? false) ||
        (pagination.nextCursor?.length ?? 0) > 512) {
      throw const FormatException('Habit pagination projection is invalid.');
    }
    return HabitListResponseDto(
      items: items,
      pagination: pagination,
      todayProgress: HabitTodayProgressResponseDto.fromJson(
        HabitContractValue.object(
          json['today_progress'],
          '$parent.today_progress',
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'items': items.map((item) => item.toJson()).toList(),
    'pagination': {
      'total': pagination.total,
      'page': pagination.page,
      'page_size': pagination.pageSize,
      'has_more': pagination.hasMore,
      'next_cursor': pagination.nextCursor,
    },
    'today_progress': todayProgress.toJson(),
  };
}

class HabitDetailResponseDto {
  HabitDetailResponseDto({
    required this.habit,
    required this.recurrence,
    required this.lifecycleStatus,
    required this.statistics,
    required this.reminderSettings,
    required this.today,
    required List<HabitDailyStatusResponseDto> history,
    required this.historyStartDate,
    required this.historyEndDate,
    required this.hasEarlierHistory,
    required this.hasEverCheckedIn,
    required this.latestCheckInDate,
    required this.challengeTimeProgress,
    required this.remainingDays,
  }) : history = List.unmodifiable(history);
  final HabitResponseDto habit;
  final HabitRecurrenceResponseDto recurrence;
  final HabitLifecycleStatusContract lifecycleStatus;
  final HabitStatisticsResponseDto statistics;
  final HabitReminderSettingsResponseDto reminderSettings;
  final HabitDailyStatusResponseDto? today;
  final List<HabitDailyStatusResponseDto> history;
  final String? historyStartDate;
  final String? historyEndDate;
  final bool hasEarlierHistory;
  final bool hasEverCheckedIn;
  final String? latestCheckInDate;
  final double challengeTimeProgress;
  final int remainingDays;

  factory HabitDetailResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitDetailResponse';
    ContractValue.requireExactKeys(json, const {
      'habit',
      'recurrence',
      'lifecycle_status',
      'statistics',
      'reminder_settings',
      'today',
      'history',
      'history_start_date',
      'history_end_date',
      'has_earlier_history',
      'has_ever_checked_in',
      'latest_check_in_date',
      'challenge_time_progress',
      'remaining_days',
    }, parent);
    final habit = HabitResponseDto.fromJson(
      HabitContractValue.object(json['habit'], '$parent.habit'),
    );
    final recurrence = HabitRecurrenceResponseDto.fromJson(
      HabitContractValue.object(json['recurrence'], '$parent.recurrence'),
    );
    if (habit.recurrenceId != recurrence.id) {
      throw const FormatException('Habit recurrence membership differs.');
    }
    final lifecycle = HabitLifecycleStatusContract.fromWireValue(
      ContractValue.nonEmptyString(json, 'lifecycle_status', parent),
    );
    final rawToday = json['today'];
    final today = rawToday == null
        ? null
        : HabitDailyStatusResponseDto.fromJson(
            HabitContractValue.object(rawToday, '$parent.today'),
          );
    if ((lifecycle == HabitLifecycleStatusContract.upcoming && today != null) ||
        (lifecycle == HabitLifecycleStatusContract.active && today == null)) {
      throw const FormatException('Habit detail today projection is invalid.');
    }
    final history = HabitContractValue.objectList(
      json['history'],
      '$parent.history',
      maximum: 120,
    ).map(HabitDailyStatusResponseDto.fromJson).toList();
    for (var index = 1; index < history.length; index++) {
      if (history[index - 1].date.compareTo(history[index].date) <= 0) {
        throw const FormatException('Habit history must descend by date.');
      }
    }
    final historyStart = ContractValue.optionalLocalDate(
      json,
      'history_start_date',
      parent,
    );
    final historyEnd = ContractValue.optionalLocalDate(
      json,
      'history_end_date',
      parent,
    );
    final hasEarlier = ContractValue.boolean(
      json,
      'has_earlier_history',
      parent,
    );
    final emptyHistoryBounds =
        history.isEmpty &&
        historyStart == null &&
        historyEnd == null &&
        !hasEarlier;
    final populatedHistoryBounds =
        history.isNotEmpty &&
        historyStart != null &&
        historyEnd != null &&
        historyStart == history.last.date &&
        historyEnd == history.first.date;
    if (!(emptyHistoryBounds || populatedHistoryBounds)) {
      throw const FormatException('Habit history bounds are inconsistent.');
    }
    final ever = ContractValue.boolean(json, 'has_ever_checked_in', parent);
    final latest = ContractValue.optionalLocalDate(
      json,
      'latest_check_in_date',
      parent,
    );
    if (ever != (latest != null)) {
      throw const FormatException('Habit check-in lock projection is invalid.');
    }
    return HabitDetailResponseDto(
      habit: habit,
      recurrence: recurrence,
      lifecycleStatus: lifecycle,
      statistics: HabitStatisticsResponseDto.fromJson(
        HabitContractValue.object(json['statistics'], '$parent.statistics'),
      ),
      reminderSettings: HabitReminderSettingsResponseDto.fromJson(
        HabitContractValue.object(
          json['reminder_settings'],
          '$parent.reminder_settings',
        ),
      ),
      today: today,
      history: history,
      historyStartDate: historyStart,
      historyEndDate: historyEnd,
      hasEarlierHistory: hasEarlier,
      hasEverCheckedIn: ever,
      latestCheckInDate: latest,
      challengeTimeProgress: HabitContractValue.ratio(
        json,
        'challenge_time_progress',
        parent,
      ),
      remainingDays: ContractValue.integer(
        json,
        'remaining_days',
        parent,
        minimum: 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'habit': habit.toJson(),
    'recurrence': recurrence.toJson(),
    'lifecycle_status': lifecycleStatus.wireValue,
    'statistics': statistics.toJson(),
    'reminder_settings': reminderSettings.toJson(),
    'today': today?.toJson(),
    'history': history.map((item) => item.toJson()).toList(),
    'history_start_date': historyStartDate,
    'history_end_date': historyEndDate,
    'has_earlier_history': hasEarlierHistory,
    'has_ever_checked_in': hasEverCheckedIn,
    'latest_check_in_date': latestCheckInDate,
    'challenge_time_progress': challengeTimeProgress,
    'remaining_days': remainingDays,
  };
}

class HabitMutationResponseDto {
  const HabitMutationResponseDto({
    required this.detail,
    required this.capability,
  });
  final HabitDetailResponseDto detail;
  final HabitScheduleCapabilityResponseDto capability;

  factory HabitMutationResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, const {
      'data_saved',
      'detail',
      'capability',
    }, 'HabitMutationResponse');
    if (json['data_saved'] != true) {
      throw const FormatException('Habit mutation must confirm saved data.');
    }
    final detail = HabitDetailResponseDto.fromJson(
      HabitContractValue.object(json['detail'], 'HabitMutationResponse.detail'),
    );
    final capability = HabitScheduleCapabilityResponseDto.fromJson(
      HabitContractValue.object(
        json['capability'],
        'HabitMutationResponse.capability',
      ),
    );
    if (detail.reminderSettings.scheduleReconciliationRequired !=
        capability.scheduleReconciliationRequired) {
      throw const FormatException('Habit reconciliation projections differ.');
    }
    return HabitMutationResponseDto(detail: detail, capability: capability);
  }

  Map<String, dynamic> toJson() => {
    'data_saved': true,
    'detail': detail.toJson(),
    'capability': capability.toJson(),
  };
}

class HabitCheckInMutationResponseDto {
  const HabitCheckInMutationResponseDto({
    required this.checkIn,
    required this.dailyStatus,
    required this.statistics,
    required this.reminderSettings,
    required this.capability,
    required this.idempotentReplay,
  });
  final HabitCheckInResponseDto? checkIn;
  final HabitDailyStatusResponseDto dailyStatus;
  final HabitStatisticsResponseDto statistics;
  final HabitReminderSettingsResponseDto reminderSettings;
  final HabitScheduleCapabilityResponseDto capability;
  final bool idempotentReplay;

  factory HabitCheckInMutationResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitCheckInMutationResponse';
    ContractValue.requireExactKeys(json, const {
      'data_saved',
      'check_in',
      'daily_status',
      'statistics',
      'reminder_settings',
      'capability',
      'idempotent_replay',
    }, parent);
    if (json['data_saved'] != true) {
      throw const FormatException('Check-in mutation must confirm saved data.');
    }
    final rawCheckIn = json['check_in'];
    final checkIn = rawCheckIn == null
        ? null
        : HabitCheckInResponseDto.fromJson(
            HabitContractValue.object(rawCheckIn, '$parent.check_in'),
          );
    final daily = HabitDailyStatusResponseDto.fromJson(
      HabitContractValue.object(json['daily_status'], '$parent.daily_status'),
    );
    if ((checkIn == null) != (daily.checkIn == null) ||
        (checkIn != null && daily.checkIn?.id != checkIn.id)) {
      throw const FormatException('Check-in mutation projection differs.');
    }
    final settings = HabitReminderSettingsResponseDto.fromJson(
      HabitContractValue.object(
        json['reminder_settings'],
        '$parent.reminder_settings',
      ),
    );
    final capability = HabitScheduleCapabilityResponseDto.fromJson(
      HabitContractValue.object(json['capability'], '$parent.capability'),
    );
    if (settings.scheduleReconciliationRequired !=
        capability.scheduleReconciliationRequired) {
      throw const FormatException(
        'Check-in reconciliation projections differ.',
      );
    }
    return HabitCheckInMutationResponseDto(
      checkIn: checkIn,
      dailyStatus: daily,
      statistics: HabitStatisticsResponseDto.fromJson(
        HabitContractValue.object(json['statistics'], '$parent.statistics'),
      ),
      reminderSettings: settings,
      capability: capability,
      idempotentReplay: ContractValue.boolean(
        json,
        'idempotent_replay',
        parent,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'data_saved': true,
    'check_in': checkIn?.toJson(),
    'daily_status': dailyStatus.toJson(),
    'statistics': statistics.toJson(),
    'reminder_settings': reminderSettings.toJson(),
    'capability': capability.toJson(),
    'idempotent_replay': idempotentReplay,
  };
}

class HabitDeleteOperationResponseDto {
  const HabitDeleteOperationResponseDto({
    required this.habitId,
    required this.deletedAt,
    required this.capability,
  });
  final String habitId;
  final DateTime deletedAt;
  final HabitScheduleCapabilityResponseDto capability;

  factory HabitDeleteOperationResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitDeleteOperationResponse';
    ContractValue.requireExactKeys(json, const {
      'data_saved',
      'habit_id',
      'deleted_at',
      'capability',
    }, parent);
    if (json['data_saved'] != true) {
      throw const FormatException('Habit delete must confirm saved data.');
    }
    return HabitDeleteOperationResponseDto(
      habitId: ContractValue.uuid(json, 'habit_id', parent),
      deletedAt: ContractValue.utcDateTime(
        json,
        'deleted_at',
        parent,
        wholeSecond: true,
      ),
      capability: HabitScheduleCapabilityResponseDto.fromJson(
        HabitContractValue.object(json['capability'], '$parent.capability'),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'data_saved': true,
    'habit_id': habitId,
    'deleted_at': HabitContractValue.utcSecond(deletedAt, 'deleted_at'),
    'capability': capability.toJson(),
  };
}

class HabitDailyStatusListResponseDto {
  HabitDailyStatusListResponseDto({
    required this.habitId,
    required this.startDate,
    required this.endDate,
    required List<HabitDailyStatusResponseDto> items,
  }) : items = List.unmodifiable(items);
  final String habitId;
  final String startDate;
  final String endDate;
  final List<HabitDailyStatusResponseDto> items;

  factory HabitDailyStatusListResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'HabitDailyStatusListResponse';
    ContractValue.requireExactKeys(json, const {
      'habit_id',
      'start_date',
      'end_date',
      'items',
    }, parent);
    final start = ContractValue.localDate(json, 'start_date', parent);
    final end = ContractValue.localDate(json, 'end_date', parent);
    final items = HabitContractValue.objectList(
      json['items'],
      '$parent.items',
      maximum: 400,
    ).map(HabitDailyStatusResponseDto.fromJson).toList();
    if (items.isEmpty || items.first.date != start || items.last.date != end) {
      throw const FormatException('Habit daily-status bounds differ.');
    }
    for (var index = 1; index < items.length; index++) {
      final expected = CivilDate.parse(items[index - 1].date).addDays(1);
      if (items[index].date != expected.format()) {
        throw const FormatException(
          'Habit daily-status dates must be contiguous.',
        );
      }
    }
    return HabitDailyStatusListResponseDto(
      habitId: ContractValue.uuid(json, 'habit_id', parent),
      startDate: start,
      endDate: end,
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
    'habit_id': habitId,
    'start_date': startDate,
    'end_date': endDate,
    'items': items.map((item) => item.toJson()).toList(),
  };
}

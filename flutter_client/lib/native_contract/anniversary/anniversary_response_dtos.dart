import '../common/pagination_response_dto.dart';
import '../notification/notification_contract_enums.dart';
import '../shared/contract_value.dart';
import 'anniversary_contract_enums.dart';
import 'anniversary_request_dtos.dart';

class AnniversaryResponseDto {
  const AnniversaryResponseDto({
    required this.id,
    required this.title,
    required this.date,
    required this.calendarType,
    required this.categoryId,
    required this.recurrenceId,
    required this.note,
    required this.importance,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  static const _keys = {
    'id',
    'title',
    'date',
    'calendar_type',
    'category_id',
    'recurrence_id',
    'note',
    'importance',
    'created_at',
    'updated_at',
    'deleted_at',
  };

  final String id;
  final String title;
  final DateTime date;
  final AnniversaryCalendarTypeContract? calendarType;
  final String? categoryId;
  final String? recurrenceId;
  final String? note;
  final AnniversaryImportanceContract? importance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory AnniversaryResponseDto.fromJson(
    Map<String, dynamic> json, {
    bool requireDeleted = false,
  }) {
    ContractValue.requireExactKeys(json, _keys, 'AnniversaryResponse');
    final id = ContractValue.nonEmptyString(json, 'id', 'AnniversaryResponse');
    AnniversaryRequestValue.uuid(id, 'AnniversaryResponse.id');
    final categoryId = ContractValue.optionalString(
      json,
      'category_id',
      'AnniversaryResponse',
    );
    AnniversaryRequestValue.optionalUuid(
      categoryId,
      'AnniversaryResponse.category_id',
    );
    final recurrenceId = ContractValue.optionalString(
      json,
      'recurrence_id',
      'AnniversaryResponse',
    );
    AnniversaryRequestValue.optionalUuid(
      recurrenceId,
      'AnniversaryResponse.recurrence_id',
    );
    final rawCalendarType = ContractValue.optionalString(
      json,
      'calendar_type',
      'AnniversaryResponse',
    );
    final rawImportance = ContractValue.optionalString(
      json,
      'importance',
      'AnniversaryResponse',
    );
    final deletedAt = ContractValue.optionalUtcDateTime(
      json,
      'deleted_at',
      'AnniversaryResponse',
      wholeSecond: true,
    );
    if (requireDeleted && deletedAt == null) {
      throw const FormatException(
        'DeletedAnniversaryResponse.deleted_at must be non-null.',
      );
    }
    return AnniversaryResponseDto(
      id: id,
      title: ContractValue.nonEmptyString(json, 'title', 'AnniversaryResponse'),
      date: ContractValue.localDateAsDateTime(
        ContractValue.localDate(json, 'date', 'AnniversaryResponse'),
        field: 'AnniversaryResponse.date',
      ),
      calendarType: rawCalendarType == null
          ? null
          : AnniversaryCalendarTypeContract.fromWireValue(rawCalendarType),
      categoryId: categoryId,
      recurrenceId: recurrenceId,
      note: ContractValue.optionalString(json, 'note', 'AnniversaryResponse'),
      importance: rawImportance == null
          ? null
          : AnniversaryImportanceContract.fromWireValue(rawImportance),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'AnniversaryResponse',
        wholeSecond: true,
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'AnniversaryResponse',
        wholeSecond: true,
      ),
      deletedAt: deletedAt,
    );
  }
}

class AnniversaryRecurrenceResponseDto {
  const AnniversaryRecurrenceResponseDto({required this.recurrenceId});

  final String recurrenceId;
  String get frequency => 'yearly';
  int get interval => 1;

  factory AnniversaryRecurrenceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'recurrence_id',
      'frequency',
      'interval',
    }, 'AnniversaryRecurrenceResponse');
    final recurrenceId = ContractValue.nonEmptyString(
      json,
      'recurrence_id',
      'AnniversaryRecurrenceResponse',
    );
    AnniversaryRequestValue.uuid(
      recurrenceId,
      'AnniversaryRecurrenceResponse.recurrence_id',
    );
    if (json['frequency'] != 'yearly' || json['interval'] != 1) {
      throw const FormatException(
        'AnniversaryRecurrenceResponse must be yearly interval 1.',
      );
    }
    return AnniversaryRecurrenceResponseDto(recurrenceId: recurrenceId);
  }
}

class AnniversaryCountdownResponseDto {
  const AnniversaryCountdownResponseDto({
    required this.relation,
    required this.days,
    required this.targetOccurrenceDate,
    required this.isoWeekday,
    required this.timezone,
    required this.calculatedAt,
  });

  final AnniversaryCountdownRelationContract relation;
  final int days;
  final DateTime targetOccurrenceDate;
  final int isoWeekday;
  final String timezone;
  final DateTime calculatedAt;

  factory AnniversaryCountdownResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'relation',
      'days',
      'target_occurrence_date',
      'iso_weekday',
      'timezone',
      'calculated_at',
    }, 'AnniversaryCountdownResponse');
    final relation = AnniversaryCountdownRelationContract.fromWireValue(
      ContractValue.nonEmptyString(
        json,
        'relation',
        'AnniversaryCountdownResponse',
      ),
    );
    final days = ContractValue.integer(
      json,
      'days',
      'AnniversaryCountdownResponse',
      minimum: 0,
    );
    if ((relation == AnniversaryCountdownRelationContract.today && days != 0) ||
        (relation != AnniversaryCountdownRelationContract.today && days < 1)) {
      throw const FormatException(
        'AnniversaryCountdownResponse.days is inconsistent with relation.',
      );
    }
    return AnniversaryCountdownResponseDto(
      relation: relation,
      days: days,
      targetOccurrenceDate: ContractValue.localDateAsDateTime(
        ContractValue.localDate(
          json,
          'target_occurrence_date',
          'AnniversaryCountdownResponse',
        ),
        field: 'AnniversaryCountdownResponse.target_occurrence_date',
      ),
      isoWeekday: ContractValue.integer(
        json,
        'iso_weekday',
        'AnniversaryCountdownResponse',
        minimum: 1,
        maximum: 7,
      ),
      timezone: ContractValue.nonEmptyString(
        json,
        'timezone',
        'AnniversaryCountdownResponse',
      ),
      calculatedAt: ContractValue.utcDateTime(
        json,
        'calculated_at',
        'AnniversaryCountdownResponse',
        wholeSecond: true,
      ),
    );
  }
}

class AnniversaryReminderTemplateResponseDto {
  const AnniversaryReminderTemplateResponseDto({
    required this.templateKey,
    required this.advanceDays,
    required this.localTime,
    required this.timezoneMode,
    required this.isEnabled,
  });

  final String templateKey;
  final int advanceDays;
  final String localTime;
  final AnniversaryReminderTimezoneModeContract timezoneMode;
  final bool isEnabled;

  factory AnniversaryReminderTemplateResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'template_key',
      'advance_days',
      'local_time',
      'timezone_mode',
      'method',
      'is_enabled',
    }, 'AnniversaryReminderTemplateResponse');
    final templateKey = ContractValue.nonEmptyString(
      json,
      'template_key',
      'AnniversaryReminderTemplateResponse',
    );
    AnniversaryRequestValue.uuid(
      templateKey,
      'AnniversaryReminderTemplateResponse.template_key',
    );
    final localTime = ContractValue.nonEmptyString(
      json,
      'local_time',
      'AnniversaryReminderTemplateResponse',
    );
    AnniversaryRequestValue.localTime(
      localTime,
      'AnniversaryReminderTemplateResponse.local_time',
    );
    if (json['timezone_mode'] != 'follow_device' || json['method'] != 'popup') {
      throw const FormatException(
        'Anniversary reminder response must use follow_device and popup.',
      );
    }
    return AnniversaryReminderTemplateResponseDto(
      templateKey: templateKey,
      advanceDays: ContractValue.integer(
        json,
        'advance_days',
        'AnniversaryReminderTemplateResponse',
        minimum: 0,
        maximum: 365,
      ),
      localTime: localTime,
      timezoneMode: AnniversaryReminderTimezoneModeContract.followDevice,
      isEnabled: ContractValue.boolean(
        json,
        'is_enabled',
        'AnniversaryReminderTemplateResponse',
      ),
    );
  }
}

class AnniversaryReminderSettingsResponseDto {
  AnniversaryReminderSettingsResponseDto({
    required this.remindersEnabled,
    required List<AnniversaryReminderTemplateResponseDto> templates,
    required this.activeReminderCount,
    required this.scheduleReconciliationRequired,
  }) : templates = List.unmodifiable(templates);

  final bool remindersEnabled;
  final List<AnniversaryReminderTemplateResponseDto> templates;
  final int activeReminderCount;
  final bool scheduleReconciliationRequired;

  factory AnniversaryReminderSettingsResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'reminders_enabled',
      'templates',
      'active_reminder_count',
      'schedule_reconciliation_required',
    }, 'AnniversaryReminderSettingsResponse');
    final rawTemplates = json['templates'];
    if (rawTemplates is! List || rawTemplates.length > 5) {
      throw const FormatException(
        'Anniversary reminder templates must be an array of at most five.',
      );
    }
    final templates = rawTemplates
        .map(
          (item) => AnniversaryReminderTemplateResponseDto.fromJson(
            _object(item, 'AnniversaryReminderSettingsResponse.templates'),
          ),
        )
        .toList(growable: false);
    final identities = templates
        .map(
          (item) =>
              '${item.advanceDays}|${item.localTime}|${item.timezoneMode.wireValue}|popup',
        )
        .toSet();
    if (identities.length != templates.length) {
      throw const FormatException(
        'Anniversary reminder settings contain duplicate templates.',
      );
    }
    final enabled = ContractValue.boolean(
      json,
      'reminders_enabled',
      'AnniversaryReminderSettingsResponse',
    );
    final count = ContractValue.integer(
      json,
      'active_reminder_count',
      'AnniversaryReminderSettingsResponse',
      minimum: 0,
      maximum: 5,
    );
    final expectedCount = enabled
        ? templates.where((item) => item.isEnabled).length
        : 0;
    if (count != expectedCount) {
      throw const FormatException(
        'Anniversary active_reminder_count is inconsistent.',
      );
    }
    return AnniversaryReminderSettingsResponseDto(
      remindersEnabled: enabled,
      templates: templates,
      activeReminderCount: count,
      scheduleReconciliationRequired: ContractValue.boolean(
        json,
        'schedule_reconciliation_required',
        'AnniversaryReminderSettingsResponse',
      ),
    );
  }
}

class AnniversaryScheduleCapabilityResponseDto {
  AnniversaryScheduleCapabilityResponseDto({
    required this.scheduleStatus,
    required this.scheduleReconciliationRequired,
    required this.notificationPermissionStatus,
    required this.exactAlarmPermissionStatus,
    required List<AnniversaryScheduleDegradationReasonContract>
    degradationReasons,
  }) : degradationReasons = List.unmodifiable(degradationReasons);

  final AnniversaryScheduleStatusContract scheduleStatus;
  final bool scheduleReconciliationRequired;
  final NotificationPermissionStatus notificationPermissionStatus;
  final ExactAlarmPermissionStatus exactAlarmPermissionStatus;
  final List<AnniversaryScheduleDegradationReasonContract> degradationReasons;

  factory AnniversaryScheduleCapabilityResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'schedule_status',
      'schedule_reconciliation_required',
      'notification_permission_status',
      'exact_alarm_permission_status',
      'degradation_reasons',
    }, 'AnniversaryScheduleCapabilityResponse');
    final rawReasons = json['degradation_reasons'];
    if (rawReasons is! List || rawReasons.any((item) => item is! String)) {
      throw const FormatException(
        'Anniversary degradation_reasons must be a string array.',
      );
    }
    final reasons = rawReasons
        .cast<String>()
        .map(AnniversaryScheduleDegradationReasonContract.fromWireValue)
        .toList(growable: false);
    if (reasons.toSet().length != reasons.length) {
      throw const FormatException(
        'Anniversary degradation_reasons must be unique.',
      );
    }
    final status = AnniversaryScheduleStatusContract.fromWireValue(
      ContractValue.nonEmptyString(
        json,
        'schedule_status',
        'AnniversaryScheduleCapabilityResponse',
      ),
    );
    final pending = ContractValue.boolean(
      json,
      'schedule_reconciliation_required',
      'AnniversaryScheduleCapabilityResponse',
    );
    final expectedPending =
        status == AnniversaryScheduleStatusContract.pendingPermission ||
        status == AnniversaryScheduleStatusContract.pendingReconciliation;
    if (pending != expectedPending) {
      throw const FormatException(
        'Anniversary schedule status and reconciliation flag are inconsistent.',
      );
    }
    return AnniversaryScheduleCapabilityResponseDto(
      scheduleStatus: status,
      scheduleReconciliationRequired: pending,
      notificationPermissionStatus: NotificationPermissionStatus.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'notification_permission_status',
          'AnniversaryScheduleCapabilityResponse',
        ),
      ),
      exactAlarmPermissionStatus: ExactAlarmPermissionStatus.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'exact_alarm_permission_status',
          'AnniversaryScheduleCapabilityResponse',
        ),
      ),
      degradationReasons: reasons,
    );
  }
}

class AnniversaryDetailResponseDto {
  const AnniversaryDetailResponseDto({
    required this.anniversary,
    required this.recurrence,
    required this.countdown,
    required this.reminderSettings,
  });

  final AnniversaryResponseDto anniversary;
  final AnniversaryRecurrenceResponseDto? recurrence;
  final AnniversaryCountdownResponseDto countdown;
  final AnniversaryReminderSettingsResponseDto reminderSettings;

  factory AnniversaryDetailResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'anniversary',
      'recurrence',
      'countdown',
      'reminder_settings',
    }, 'AnniversaryDetailResponse');
    final anniversary = AnniversaryResponseDto.fromJson(
      _object(json['anniversary'], 'AnniversaryDetailResponse.anniversary'),
    );
    final recurrence = json['recurrence'] == null
        ? null
        : AnniversaryRecurrenceResponseDto.fromJson(
            _object(json['recurrence'], 'AnniversaryDetailResponse.recurrence'),
          );
    if (anniversary.calendarType != AnniversaryCalendarTypeContract.solar ||
        anniversary.deletedAt != null ||
        ((anniversary.recurrenceId == null) != (recurrence == null)) ||
        (recurrence != null &&
            recurrence.recurrenceId != anniversary.recurrenceId)) {
      throw const FormatException(
        'AnniversaryDetailResponse projection is inconsistent.',
      );
    }
    return AnniversaryDetailResponseDto(
      anniversary: anniversary,
      recurrence: recurrence,
      countdown: AnniversaryCountdownResponseDto.fromJson(
        _object(json['countdown'], 'AnniversaryDetailResponse.countdown'),
      ),
      reminderSettings: AnniversaryReminderSettingsResponseDto.fromJson(
        _object(
          json['reminder_settings'],
          'AnniversaryDetailResponse.reminder_settings',
        ),
      ),
    );
  }
}

class AnniversaryMutationResponseDto {
  const AnniversaryMutationResponseDto({
    required this.detail,
    required this.capability,
  });

  final AnniversaryDetailResponseDto detail;
  final AnniversaryScheduleCapabilityResponseDto capability;

  factory AnniversaryMutationResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'data_saved',
      'detail',
      'capability',
    }, 'AnniversaryMutationResponse');
    if (json['data_saved'] != true) {
      throw const FormatException(
        'Successful AnniversaryMutationResponse must have data_saved=true.',
      );
    }
    final detail = AnniversaryDetailResponseDto.fromJson(
      _object(json['detail'], 'AnniversaryMutationResponse.detail'),
    );
    final capability = AnniversaryScheduleCapabilityResponseDto.fromJson(
      _object(json['capability'], 'AnniversaryMutationResponse.capability'),
    );
    if (detail.reminderSettings.scheduleReconciliationRequired !=
        capability.scheduleReconciliationRequired) {
      throw const FormatException(
        'Anniversary mutation reconciliation projections disagree.',
      );
    }
    return AnniversaryMutationResponseDto(
      detail: detail,
      capability: capability,
    );
  }
}

class AnniversaryDetailViewResponseDto {
  const AnniversaryDetailViewResponseDto({
    required this.detail,
    required this.capability,
  });

  final AnniversaryDetailResponseDto detail;
  final AnniversaryScheduleCapabilityResponseDto capability;

  factory AnniversaryDetailViewResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'detail',
      'capability',
    }, 'AnniversaryDetailViewResponse');
    return AnniversaryDetailViewResponseDto(
      detail: AnniversaryDetailResponseDto.fromJson(
        _object(json['detail'], 'AnniversaryDetailViewResponse.detail'),
      ),
      capability: AnniversaryScheduleCapabilityResponseDto.fromJson(
        _object(json['capability'], 'AnniversaryDetailViewResponse.capability'),
      ),
    );
  }
}

class AnniversaryOccurrenceSummaryResponseDto {
  const AnniversaryOccurrenceSummaryResponseDto({
    required this.anniversaryId,
    required this.occurrenceKey,
    required this.occurrenceDate,
    required this.sourceDate,
    required this.title,
    required this.calendarType,
    required this.isRepeating,
    required this.yearsElapsed,
    required this.categoryId,
    required this.importance,
    required this.hasActiveReminders,
    required this.reminderCount,
  });

  final String anniversaryId;
  final String occurrenceKey;
  final DateTime occurrenceDate;
  final DateTime sourceDate;
  final String title;
  final AnniversaryCalendarTypeContract calendarType;
  final bool isRepeating;
  final int yearsElapsed;
  final String? categoryId;
  final AnniversaryImportanceContract? importance;
  final bool hasActiveReminders;
  final int reminderCount;

  factory AnniversaryOccurrenceSummaryResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'anniversary_id',
      'occurrence_key',
      'occurrence_date',
      'source_date',
      'title',
      'calendar_type',
      'is_repeating',
      'years_elapsed',
      'category_id',
      'importance',
      'has_active_reminders',
      'reminder_count',
    }, 'AnniversaryOccurrenceSummaryResponse');
    final anniversaryId = ContractValue.nonEmptyString(
      json,
      'anniversary_id',
      'AnniversaryOccurrenceSummaryResponse',
    );
    final occurrenceKey = ContractValue.nonEmptyString(
      json,
      'occurrence_key',
      'AnniversaryOccurrenceSummaryResponse',
    );
    AnniversaryRequestValue.uuid(
      anniversaryId,
      'AnniversaryOccurrenceSummaryResponse.anniversary_id',
    );
    AnniversaryRequestValue.uuid(
      occurrenceKey,
      'AnniversaryOccurrenceSummaryResponse.occurrence_key',
    );
    final categoryId = ContractValue.optionalString(
      json,
      'category_id',
      'AnniversaryOccurrenceSummaryResponse',
    );
    AnniversaryRequestValue.optionalUuid(
      categoryId,
      'AnniversaryOccurrenceSummaryResponse.category_id',
    );
    final rawImportance = ContractValue.optionalString(
      json,
      'importance',
      'AnniversaryOccurrenceSummaryResponse',
    );
    if (json['calendar_type'] != 'solar') {
      throw const FormatException(
        'Anniversary occurrence calendar_type must be solar.',
      );
    }
    final repeating = ContractValue.boolean(
      json,
      'is_repeating',
      'AnniversaryOccurrenceSummaryResponse',
    );
    final years = ContractValue.integer(
      json,
      'years_elapsed',
      'AnniversaryOccurrenceSummaryResponse',
      minimum: 0,
    );
    final active = ContractValue.boolean(
      json,
      'has_active_reminders',
      'AnniversaryOccurrenceSummaryResponse',
    );
    final count = ContractValue.integer(
      json,
      'reminder_count',
      'AnniversaryOccurrenceSummaryResponse',
      minimum: 0,
      maximum: 5,
    );
    final occurrenceDate = ContractValue.localDateAsDateTime(
      ContractValue.localDate(
        json,
        'occurrence_date',
        'AnniversaryOccurrenceSummaryResponse',
      ),
      field: 'AnniversaryOccurrenceSummaryResponse.occurrence_date',
    );
    final sourceDate = ContractValue.localDateAsDateTime(
      ContractValue.localDate(
        json,
        'source_date',
        'AnniversaryOccurrenceSummaryResponse',
      ),
      field: 'AnniversaryOccurrenceSummaryResponse.source_date',
    );
    if ((!active && count != 0) || (active && count == 0)) {
      throw const FormatException(
        'Anniversary occurrence reminder projection is inconsistent.',
      );
    }
    if (!repeating && (years != 0 || occurrenceDate != sourceDate)) {
      throw const FormatException(
        'One-time Anniversary occurrence projection is inconsistent.',
      );
    }
    return AnniversaryOccurrenceSummaryResponseDto(
      anniversaryId: anniversaryId,
      occurrenceKey: occurrenceKey,
      occurrenceDate: occurrenceDate,
      sourceDate: sourceDate,
      title: ContractValue.nonEmptyString(
        json,
        'title',
        'AnniversaryOccurrenceSummaryResponse',
      ),
      calendarType: AnniversaryCalendarTypeContract.solar,
      isRepeating: repeating,
      yearsElapsed: years,
      categoryId: categoryId,
      importance: rawImportance == null
          ? null
          : AnniversaryImportanceContract.fromWireValue(rawImportance),
      hasActiveReminders: active,
      reminderCount: count,
    );
  }
}

class AnniversaryOccurrenceListResponseDto {
  AnniversaryOccurrenceListResponseDto({
    required List<AnniversaryOccurrenceSummaryResponseDto> items,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<AnniversaryOccurrenceSummaryResponseDto> items;
  final bool hasMore;
  final String? nextCursor;

  factory AnniversaryOccurrenceListResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'items',
      'has_more',
      'next_cursor',
    }, 'AnniversaryOccurrenceListResponse');
    final rawItems = json['items'];
    if (rawItems is! List || rawItems.length > 500) {
      throw const FormatException(
        'Anniversary occurrence items must be an array of at most 500.',
      );
    }
    final items = rawItems
        .map(
          (item) => AnniversaryOccurrenceSummaryResponseDto.fromJson(
            _object(item, 'AnniversaryOccurrenceListResponse.items'),
          ),
        )
        .toList(growable: false);
    final hasMore = ContractValue.boolean(
      json,
      'has_more',
      'AnniversaryOccurrenceListResponse',
    );
    final nextCursor = ContractValue.optionalString(
      json,
      'next_cursor',
      'AnniversaryOccurrenceListResponse',
    );
    if (hasMore != (nextCursor != null)) {
      throw const FormatException(
        'Anniversary occurrence cursor and has_more are inconsistent.',
      );
    }
    if (nextCursor != null &&
        !RegExp(r'^annocc1\.[A-Za-z0-9_-]{20,2048}$').hasMatch(nextCursor)) {
      throw const FormatException('Anniversary next_cursor is malformed.');
    }
    return AnniversaryOccurrenceListResponseDto(
      items: items,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }
}

class AnniversaryDeleteOperationResponseDto {
  const AnniversaryDeleteOperationResponseDto({
    required this.anniversary,
    required this.capability,
  });

  final AnniversaryResponseDto anniversary;
  final AnniversaryScheduleCapabilityResponseDto capability;

  factory AnniversaryDeleteOperationResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractValue.requireExactKeys(json, {
      'data_saved',
      'commit',
      'capability',
    }, 'AnniversaryDeleteOperationResponse');
    if (json['data_saved'] != true) {
      throw const FormatException(
        'Successful Anniversary delete must have data_saved=true.',
      );
    }
    final commit = _object(
      json['commit'],
      'AnniversaryDeleteOperationResponse.commit',
    );
    ContractValue.requireExactKeys(commit, {
      'anniversary',
      'schedule_reconciliation_required',
    }, 'AnniversaryDeleteCommitResponse');
    final capability = AnniversaryScheduleCapabilityResponseDto.fromJson(
      _object(
        json['capability'],
        'AnniversaryDeleteOperationResponse.capability',
      ),
    );
    if (ContractValue.boolean(
          commit,
          'schedule_reconciliation_required',
          'AnniversaryDeleteCommitResponse',
        ) !=
        capability.scheduleReconciliationRequired) {
      throw const FormatException(
        'Anniversary delete reconciliation projections disagree.',
      );
    }
    return AnniversaryDeleteOperationResponseDto(
      anniversary: AnniversaryResponseDto.fromJson(
        _object(commit['anniversary'], 'AnniversaryDeleteCommitResponse'),
        requireDeleted: true,
      ),
      capability: capability,
    );
  }
}

class AnniversarySummaryResponseDto {
  const AnniversarySummaryResponseDto({
    required this.anniversary,
    required this.countdown,
  });

  final AnniversaryResponseDto anniversary;
  final AnniversaryCountdownResponseDto countdown;

  factory AnniversarySummaryResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'anniversary',
      'countdown',
    }, 'AnniversarySummaryResponse');
    final anniversary = AnniversaryResponseDto.fromJson(
      _object(json['anniversary'], 'AnniversarySummaryResponse.anniversary'),
    );
    if (anniversary.calendarType != AnniversaryCalendarTypeContract.solar ||
        anniversary.deletedAt != null) {
      throw const FormatException(
        'AnniversarySummaryResponse must contain an active solar Anniversary.',
      );
    }
    return AnniversarySummaryResponseDto(
      anniversary: anniversary,
      countdown: AnniversaryCountdownResponseDto.fromJson(
        _object(json['countdown'], 'AnniversarySummaryResponse.countdown'),
      ),
    );
  }
}

class AnniversaryListResponseDto {
  const AnniversaryListResponseDto({
    required this.items,
    required this.pagination,
  });

  final List<AnniversarySummaryResponseDto> items;
  final PaginationResponseDto pagination;

  factory AnniversaryListResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'items',
      'pagination',
    }, 'AnniversaryListResponse');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'AnniversaryListResponse.items must be an array.',
      );
    }
    return AnniversaryListResponseDto(
      items: List<AnniversarySummaryResponseDto>.unmodifiable(
        rawItems.map(
          (item) => AnniversarySummaryResponseDto.fromJson(
            _object(item, 'AnniversaryListResponse.items'),
          ),
        ),
      ),
      pagination: PaginationResponseDto.fromJson(
        _object(json['pagination'], 'AnniversaryListResponse.pagination'),
      ),
    );
  }
}

Map<String, dynamic> _object(Object? value, String parent) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$parent must be an object.');
}

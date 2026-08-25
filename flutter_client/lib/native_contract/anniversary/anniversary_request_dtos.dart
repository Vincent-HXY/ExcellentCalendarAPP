import '../shared/contract_value.dart';
import 'anniversary_contract_enums.dart';

class AnniversaryRecurrenceRuleInputDto {
  const AnniversaryRecurrenceRuleInputDto.yearly()
    : frequency = 'yearly',
      interval = 1;

  final String frequency;
  final int interval;

  Map<String, dynamic> toJson() {
    if (frequency != 'yearly' || interval != 1) {
      throw const FormatException(
        'Anniversary recurrence must be yearly with interval 1.',
      );
    }
    return {'frequency': frequency, 'interval': interval};
  }
}

class AnniversaryReminderTemplateInputDto {
  const AnniversaryReminderTemplateInputDto({
    required this.advanceDays,
    required this.localTime,
    required this.isEnabled,
  });

  final int advanceDays;
  final String localTime;
  final bool isEnabled;

  Map<String, dynamic> toJson() {
    if (advanceDays < 0 || advanceDays > 365) {
      throw const FormatException(
        'Anniversary reminder advance_days must be between 0 and 365.',
      );
    }
    AnniversaryRequestValue.localTime(
      localTime,
      'AnniversaryReminderTemplateInput.local_time',
    );
    return {
      'advance_days': advanceDays,
      'local_time': localTime,
      'method': 'popup',
      'is_enabled': isEnabled,
    };
  }
}

class AnniversaryReminderPlanInputDto {
  AnniversaryReminderPlanInputDto({
    required this.remindersEnabled,
    required List<AnniversaryReminderTemplateInputDto> templates,
  }) : templates = List.unmodifiable(templates);

  final bool remindersEnabled;
  final List<AnniversaryReminderTemplateInputDto> templates;

  Map<String, dynamic> toJson() {
    if (templates.length > 5) {
      throw const FormatException(
        'Anniversary reminder plan cannot contain more than five templates.',
      );
    }
    final serialized = templates.map((item) => item.toJson()).toList();
    final identities = serialized
        .map(
          (item) =>
              '${item['advance_days']}|${item['local_time']}|${item['method']}',
        )
        .toSet();
    if (identities.length != serialized.length) {
      throw const FormatException(
        'Anniversary reminder plan contains duplicate templates.',
      );
    }
    return {'reminders_enabled': remindersEnabled, 'templates': serialized};
  }
}

class CreateAnniversaryRequestDto {
  const CreateAnniversaryRequestDto({
    required this.title,
    required this.date,
    required this.calendarType,
    required this.categoryId,
    required this.recurrence,
    required this.note,
    required this.importance,
    required this.timezone,
    required this.reminderPlan,
  });

  final String title;
  final DateTime date;
  final AnniversaryCalendarTypeContract calendarType;
  final String? categoryId;
  final AnniversaryRecurrenceRuleInputDto? recurrence;
  final String? note;
  final AnniversaryImportanceContract importance;
  final String timezone;
  final AnniversaryReminderPlanInputDto reminderPlan;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.nonEmpty(title, 'CreateAnniversaryRequest.title');
    AnniversaryRequestValue.optionalUuid(
      categoryId,
      'CreateAnniversaryRequest.category_id',
    );
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'CreateAnniversaryRequest.timezone',
    );
    return {
      'title': title,
      'date': AnniversaryRequestValue.localDate(date),
      'calendar_type': calendarType.wireValue,
      'category_id': categoryId,
      'recurrence': recurrence?.toJson(),
      'note': note,
      'importance': importance.wireValue,
      'timezone': timezone,
      'reminder_plan': reminderPlan.toJson(),
    };
  }
}

class UpdateAnniversaryRequestDto {
  const UpdateAnniversaryRequestDto({
    required this.id,
    required this.expectedUpdatedAt,
    required this.title,
    required this.date,
    required this.calendarType,
    required this.categoryId,
    required this.recurrence,
    required this.note,
    required this.importance,
    required this.timezone,
    required this.reminderPlan,
  });

  final String id;
  final DateTime expectedUpdatedAt;
  final String title;
  final DateTime date;
  final AnniversaryCalendarTypeContract calendarType;
  final String? categoryId;
  final AnniversaryRecurrenceRuleInputDto? recurrence;
  final String? note;
  final AnniversaryImportanceContract importance;
  final String timezone;
  final AnniversaryReminderPlanInputDto? reminderPlan;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.uuid(id, 'UpdateAnniversaryRequest.id');
    AnniversaryRequestValue.nonEmpty(title, 'UpdateAnniversaryRequest.title');
    AnniversaryRequestValue.optionalUuid(
      categoryId,
      'UpdateAnniversaryRequest.category_id',
    );
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'UpdateAnniversaryRequest.timezone',
    );
    return {
      'id': id,
      'expected_updated_at': ContractValue.formatUtcSecond(
        expectedUpdatedAt,
        field: 'UpdateAnniversaryRequest.expected_updated_at',
      ),
      'title': title,
      'date': AnniversaryRequestValue.localDate(date),
      'calendar_type': calendarType.wireValue,
      'category_id': categoryId,
      'recurrence': recurrence?.toJson(),
      'note': note,
      'importance': importance.wireValue,
      'timezone': timezone,
      if (reminderPlan != null) 'reminder_plan': reminderPlan!.toJson(),
    };
  }
}

class SetAnniversaryRemindersEnabledRequestDto {
  const SetAnniversaryRemindersEnabledRequestDto({
    required this.id,
    required this.remindersEnabled,
    required this.timezone,
  });

  final String id;
  final bool remindersEnabled;
  final String timezone;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.uuid(
      id,
      'SetAnniversaryRemindersEnabledRequest.id',
    );
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'SetAnniversaryRemindersEnabledRequest.timezone',
    );
    return {
      'id': id,
      'reminders_enabled': remindersEnabled,
      'timezone': timezone,
    };
  }
}

class ListAnniversaryOccurrencesRequestDto {
  ListAnniversaryOccurrencesRequestDto({
    required this.rangeStartDate,
    required this.rangeEndDate,
    required this.timezone,
    required List<String> categoryIds,
    required List<AnniversaryImportanceContract> importance,
    required this.cursor,
    required this.pageSize,
  }) : categoryIds = List.unmodifiable(categoryIds),
       importance = List.unmodifiable(importance);

  final DateTime rangeStartDate;
  final DateTime rangeEndDate;
  final String timezone;
  final List<String> categoryIds;
  final List<AnniversaryImportanceContract> importance;
  final String? cursor;
  final int pageSize;

  Map<String, dynamic> toJson() {
    final start = DateTime.utc(
      rangeStartDate.year,
      rangeStartDate.month,
      rangeStartDate.day,
    );
    final end = DateTime.utc(
      rangeEndDate.year,
      rangeEndDate.month,
      rangeEndDate.day,
    );
    final days = end.difference(start).inDays;
    if (days < 1 || days > 400) {
      throw const FormatException(
        'Anniversary occurrence range must contain 1 to 400 natural days.',
      );
    }
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'ListAnniversaryOccurrencesRequest.timezone',
    );
    if (categoryIds.length > 100 ||
        categoryIds.toSet().length != categoryIds.length) {
      throw const FormatException(
        'Anniversary occurrence categories must be unique and at most 100.',
      );
    }
    for (final id in categoryIds) {
      AnniversaryRequestValue.uuid(
        id,
        'ListAnniversaryOccurrencesRequest.category_ids',
      );
    }
    if (importance.toSet().length != importance.length) {
      throw const FormatException(
        'Anniversary occurrence importance filters must be unique.',
      );
    }
    if (cursor != null &&
        !RegExp(r'^annocc1\.[A-Za-z0-9_-]{20,2048}$').hasMatch(cursor!)) {
      throw const FormatException('Anniversary occurrence cursor is invalid.');
    }
    if (pageSize < 1 || pageSize > 500) {
      throw const FormatException(
        'Anniversary occurrence page_size must be between 1 and 500.',
      );
    }
    return {
      'range_start_date': AnniversaryRequestValue.localDate(rangeStartDate),
      'range_end_date': AnniversaryRequestValue.localDate(rangeEndDate),
      'timezone': timezone,
      'category_ids': categoryIds,
      'importance': importance
          .map((item) => item.wireValue)
          .toList(growable: false),
      'cursor': cursor,
      'page_size': pageSize,
    };
  }
}

class DeleteAnniversaryRequestDto {
  const DeleteAnniversaryRequestDto(this.id);
  final String id;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.uuid(id, 'DeleteAnniversaryRequest.id');
    return {'id': id};
  }
}

class GetAnniversaryDetailRequestDto {
  const GetAnniversaryDetailRequestDto({
    required this.id,
    required this.timezone,
  });

  final String id;
  final String timezone;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.uuid(id, 'GetAnniversaryDetailRequest.id');
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'GetAnniversaryDetailRequest.timezone',
    );
    return {'id': id, 'timezone': timezone};
  }
}

class AnniversaryPaginationRequestDto {
  const AnniversaryPaginationRequestDto({
    this.page = 1,
    this.pageSize = 20,
    this.cursor,
  });

  final int? page;
  final int? pageSize;
  final String? cursor;

  Map<String, dynamic> toJson() {
    if (page != null && page! < 1) {
      throw const FormatException(
        'AnniversaryPaginationRequest.page must be positive.',
      );
    }
    if (pageSize != null && (pageSize! < 1 || pageSize! > 200)) {
      throw const FormatException(
        'AnniversaryPaginationRequest.page_size must be between 1 and 200.',
      );
    }
    return {'page': page, 'page_size': pageSize, 'cursor': cursor};
  }
}

class ListAnniversariesRequestDto {
  const ListAnniversariesRequestDto({
    required this.timezone,
    this.categoryIds,
    this.importance,
    this.pagination,
    this.sortBy,
    this.sortDirection,
  });

  final String timezone;
  final List<String>? categoryIds;
  final List<AnniversaryImportanceContract>? importance;
  final AnniversaryPaginationRequestDto? pagination;
  final AnniversarySortByContract? sortBy;
  final AnniversarySortDirectionContract? sortDirection;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'ListAnniversariesRequest.timezone',
    );
    final categories = categoryIds;
    if (categories != null) {
      if (categories.isEmpty ||
          categories.toSet().length != categories.length) {
        throw const FormatException(
          'ListAnniversariesRequest.category_ids must be non-empty and unique.',
        );
      }
      for (final id in categories) {
        AnniversaryRequestValue.uuid(
          id,
          'ListAnniversariesRequest.category_ids',
        );
      }
    }
    final importanceValues = importance;
    if (importanceValues != null &&
        (importanceValues.isEmpty ||
            importanceValues.toSet().length != importanceValues.length)) {
      throw const FormatException(
        'ListAnniversariesRequest.importance must be non-empty and unique.',
      );
    }
    return {
      'timezone': timezone,
      if (categories != null)
        'category_ids': List<String>.unmodifiable(categories),
      if (importanceValues != null)
        'importance': importanceValues
            .map((value) => value.wireValue)
            .toList(growable: false),
      if (pagination != null) 'pagination': pagination!.toJson(),
      if (sortBy != null) 'sort_by': sortBy!.wireValue,
      if (sortDirection != null) 'sort_direction': sortDirection!.wireValue,
    };
  }
}

class PreviewAnniversaryCountdownRequestDto {
  const PreviewAnniversaryCountdownRequestDto({
    required this.date,
    required this.calendarType,
    required this.recurrence,
    required this.timezone,
  });

  final DateTime date;
  final AnniversaryCalendarTypeContract calendarType;
  final AnniversaryRecurrenceRuleInputDto? recurrence;
  final String timezone;

  Map<String, dynamic> toJson() {
    AnniversaryRequestValue.nonEmpty(
      timezone,
      'PreviewAnniversaryCountdownRequest.timezone',
    );
    return {
      'date': AnniversaryRequestValue.localDate(date),
      'calendar_type': calendarType.wireValue,
      'recurrence': recurrence?.toJson(),
      'timezone': timezone,
    };
  }
}

abstract final class AnniversaryRequestValue {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static void nonEmpty(String value, String field) {
    if (value.isEmpty) throw FormatException('$field must be non-empty.');
  }

  static void uuid(String value, String field) {
    if (!_uuidPattern.hasMatch(value)) {
      throw FormatException('$field must be a UUID.');
    }
  }

  static void optionalUuid(String? value, String field) {
    if (value != null) uuid(value, field);
  }

  static String localDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static void localTime(String value, String field) {
    if (!RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) {
      throw FormatException('$field must be HH:mm.');
    }
  }
}

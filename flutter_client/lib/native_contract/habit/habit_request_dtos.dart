import '../common/pagination_request_dto.dart';
import '../shared/contract_value.dart';
import 'habit_contract_enums.dart';
import 'habit_contract_value.dart';

class HabitRecurrenceRuleInputDto {
  const HabitRecurrenceRuleInputDto();

  Map<String, dynamic> toJson() => const {
    'frequency': 'daily',
    'interval': 1,
    'timezone_mode': 'follow_device',
  };
}

class HabitReminderPlanInputDto {
  const HabitReminderPlanInputDto.disabled()
    : isEnabled = false,
      localTime = null;
  const HabitReminderPlanInputDto.enabled(this.localTime) : isEnabled = true;

  final bool isEnabled;
  final String? localTime;

  Map<String, dynamic> toJson() {
    if (isEnabled) {
      HabitContractValue.localTime(
        {'local_time': localTime},
        'local_time',
        'HabitReminderPlanInput',
      );
    } else if (localTime != null) {
      throw const FormatException('Disabled reminder local_time must be null.');
    }
    return {
      'is_enabled': isEnabled,
      'local_time': localTime,
      'timezone_mode': 'follow_device',
      'method': 'popup',
    };
  }
}

class CreateHabitRequestDto {
  const CreateHabitRequestDto({
    required this.title,
    required this.description,
    required this.categoryId,
    required this.targetCountHundredths,
    required this.unit,
    required this.startDate,
    required this.endDate,
    required this.reminder,
    required this.timezone,
  });

  final String title;
  final String? description;
  final String? categoryId;
  final int? targetCountHundredths;
  final String? unit;
  final String startDate;
  final String endDate;
  final HabitReminderPlanInputDto reminder;
  final String timezone;

  Map<String, dynamic> toJson() {
    _validateHabitDraft(
      title: title,
      description: description,
      categoryId: categoryId,
      targetCountHundredths: targetCountHundredths,
      unit: unit,
      startDate: startDate,
      endDate: endDate,
      timezone: timezone,
    );
    return {
      'title': title,
      'description': description,
      'category_id': categoryId,
      'recurrence': const HabitRecurrenceRuleInputDto().toJson(),
      'target_count_hundredths': targetCountHundredths,
      'unit': unit,
      'start_date': startDate,
      'end_date': endDate,
      'reminder': reminder.toJson(),
      'timezone': timezone,
    };
  }
}

class UpdateHabitRequestDto {
  const UpdateHabitRequestDto({
    required this.id,
    required this.expectedUpdatedAt,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.targetCountHundredths,
    required this.unit,
    required this.startDate,
    required this.endDate,
    required this.timezone,
    this.reminder,
    this.replaceReminder = false,
  });

  final String id;
  final DateTime expectedUpdatedAt;
  final String title;
  final String? description;
  final String? categoryId;
  final int? targetCountHundredths;
  final String? unit;
  final String startDate;
  final String endDate;
  final String timezone;
  final HabitReminderPlanInputDto? reminder;
  final bool replaceReminder;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': id}, 'id', 'UpdateHabitRequest');
    _validateHabitDraft(
      title: title,
      description: description,
      categoryId: categoryId,
      targetCountHundredths: targetCountHundredths,
      unit: unit,
      startDate: startDate,
      endDate: endDate,
      timezone: timezone,
    );
    if (replaceReminder && reminder == null) {
      throw const FormatException('Replacement reminder is required.');
    }
    return {
      'id': id,
      'expected_updated_at': HabitContractValue.utcSecond(
        expectedUpdatedAt,
        'UpdateHabitRequest.expected_updated_at',
      ),
      'title': title,
      'description': description,
      'category_id': categoryId,
      'target_count_hundredths': targetCountHundredths,
      'unit': unit,
      'start_date': startDate,
      'end_date': endDate,
      if (replaceReminder) 'reminder': reminder!.toJson(),
      'timezone': timezone,
    };
  }
}

class ListHabitsRequestDto {
  const ListHabitsRequestDto({
    required this.timezone,
    this.lifecycleStatuses,
    this.categoryIds,
    this.pagination = const PaginationRequestDto(
      page: 1,
      pageSize: 20,
      sortBy: null,
      sortDirection: null,
    ),
  });

  final String timezone;
  final List<HabitLifecycleStatusContract>? lifecycleStatuses;
  final List<String>? categoryIds;
  final PaginationRequestDto pagination;

  Map<String, dynamic> toJson() {
    _timezone(timezone, 'ListHabitsRequest');
    final lifecycles = lifecycleStatuses;
    if (lifecycles != null &&
        (lifecycles.isEmpty ||
            lifecycles.length > 4 ||
            lifecycles.toSet().length != lifecycles.length)) {
      throw const FormatException('Habit lifecycle filters are invalid.');
    }
    final categories = categoryIds;
    if (categories != null &&
        (categories.isEmpty ||
            categories.length > 100 ||
            categories.toSet().length != categories.length ||
            categories.any((item) => item.isEmpty || item.length > 512))) {
      throw const FormatException('Habit category filters are invalid.');
    }
    final rawPagination = pagination.toJson();
    final pageSize = rawPagination['page_size'];
    if (pageSize is int && pageSize > 100 ||
        rawPagination['sort_by'] != null ||
        rawPagination['sort_direction'] != null) {
      throw const FormatException('Habit pagination is invalid.');
    }
    final result = <String, dynamic>{
      'timezone': timezone,
      'pagination': rawPagination,
    };
    if (lifecycles != null) {
      result['lifecycle_statuses'] = lifecycles
          .map((item) => item.wireValue)
          .toList();
    }
    if (categories != null) {
      result['category_ids'] = categories;
    }
    return result;
  }
}

class GetHabitDetailRequestDto {
  const GetHabitDetailRequestDto({
    required this.id,
    required this.timezone,
    this.historyPageSize = 30,
  });
  final String id;
  final String timezone;
  final int historyPageSize;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': id}, 'id', 'GetHabitDetailRequest');
    _timezone(timezone, 'GetHabitDetailRequest');
    if (historyPageSize < 1 || historyPageSize > 120) {
      throw const FormatException('history_page_size must be 1..120.');
    }
    return {
      'id': id,
      'timezone': timezone,
      'history_page_size': historyPageSize,
    };
  }
}

class HabitOptimisticRequestDto {
  const HabitOptimisticRequestDto({
    required this.id,
    required this.expectedUpdatedAt,
    required this.timezone,
  });
  final String id;
  final DateTime expectedUpdatedAt;
  final String timezone;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': id}, 'id', 'HabitOptimisticRequest');
    _timezone(timezone, 'HabitOptimisticRequest');
    return {
      'id': id,
      'expected_updated_at': HabitContractValue.utcSecond(
        expectedUpdatedAt,
        'HabitOptimisticRequest.expected_updated_at',
      ),
      'timezone': timezone,
    };
  }
}

class HabitCheckInRequestDto {
  const HabitCheckInRequestDto({
    required this.habitId,
    required this.checkDate,
    required this.status,
    required this.completedCountHundredths,
    required this.note,
    required this.timezone,
  });
  final String habitId;
  final String checkDate;
  final HabitCheckInStatusContract status;
  final int? completedCountHundredths;
  final String? note;
  final String timezone;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': habitId}, 'id', 'HabitCheckInRequest');
    ContractValue.validateLocalDate(
      checkDate,
      field: 'HabitCheckInRequest.check_date',
    );
    _timezone(timezone, 'HabitCheckInRequest');
    _quantity(completedCountHundredths, nullable: true);
    if (status == HabitCheckInStatusContract.partial &&
        completedCountHundredths == null) {
      throw const FormatException('Partial check-in requires quantity.');
    }
    if (status == HabitCheckInStatusContract.skipped &&
        completedCountHundredths != null) {
      throw const FormatException('Skipped check-in forbids quantity.');
    }
    if (note != null && note!.runes.length > 500) {
      throw const FormatException('Habit note is too long.');
    }
    return {
      'habit_id': habitId,
      'check_date': checkDate,
      'status': status.wireValue,
      'completed_count_hundredths': completedCountHundredths,
      'note': note,
      'timezone': timezone,
    };
  }
}

class ClearHabitCheckInRequestDto {
  const ClearHabitCheckInRequestDto({
    required this.habitId,
    required this.checkDate,
    required this.timezone,
  });
  final String habitId;
  final String checkDate;
  final String timezone;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': habitId}, 'id', 'ClearHabitCheckInRequest');
    ContractValue.validateLocalDate(
      checkDate,
      field: 'ClearHabitCheckInRequest.check_date',
    );
    _timezone(timezone, 'ClearHabitCheckInRequest');
    return {'habit_id': habitId, 'check_date': checkDate, 'timezone': timezone};
  }
}

class ListHabitDailyStatusesRequestDto {
  const ListHabitDailyStatusesRequestDto({
    required this.habitId,
    required this.startDate,
    required this.endDate,
    required this.timezone,
  });
  final String habitId;
  final String startDate;
  final String endDate;
  final String timezone;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': habitId}, 'id', 'DailyStatusListRequest');
    ContractValue.validateLocalDate(startDate, field: 'start_date');
    ContractValue.validateLocalDate(endDate, field: 'end_date');
    _timezone(timezone, 'DailyStatusListRequest');
    return {
      'habit_id': habitId,
      'start_date': startDate,
      'end_date': endDate,
      'timezone': timezone,
    };
  }
}

class SetHabitReminderRequestDto {
  const SetHabitReminderRequestDto({
    required this.habitId,
    required this.expectedUpdatedAt,
    required this.reminder,
    required this.timezone,
  });
  final String habitId;
  final DateTime expectedUpdatedAt;
  final HabitReminderPlanInputDto reminder;
  final String timezone;

  Map<String, dynamic> toJson() {
    ContractValue.uuid({'id': habitId}, 'id', 'SetHabitReminderRequest');
    _timezone(timezone, 'SetHabitReminderRequest');
    return {
      'habit_id': habitId,
      'expected_updated_at': HabitContractValue.utcSecond(
        expectedUpdatedAt,
        'SetHabitReminderRequest.expected_updated_at',
      ),
      'reminder': reminder.toJson(),
      'timezone': timezone,
    };
  }
}

void _validateHabitDraft({
  required String title,
  required String? description,
  required String? categoryId,
  required int? targetCountHundredths,
  required String? unit,
  required String startDate,
  required String endDate,
  required String timezone,
}) {
  if (title.isEmpty || title.runes.length > 80) {
    throw const FormatException('Habit title must contain 1..80 code points.');
  }
  if (description != null && description.runes.length > 2000) {
    throw const FormatException('Habit description is too long.');
  }
  if (categoryId != null && categoryId.isEmpty) {
    throw const FormatException('Habit category_id cannot be empty.');
  }
  if ((targetCountHundredths == null) != (unit == null)) {
    throw const FormatException('Habit target and unit must be paired.');
  }
  _quantity(targetCountHundredths, nullable: true);
  if (unit != null && (unit.isEmpty || unit.runes.length > 32)) {
    throw const FormatException('Habit unit must contain 1..32 code points.');
  }
  ContractValue.validateLocalDate(startDate, field: 'Habit.start_date');
  ContractValue.validateLocalDate(endDate, field: 'Habit.end_date');
  _timezone(timezone, 'Habit');
}

void _quantity(int? value, {required bool nullable}) {
  if (value == null && nullable) return;
  if (value == null || value < 1 || value > HabitContractValue.maxSafeInteger) {
    throw const FormatException(
      'Habit quantity is outside safe integer range.',
    );
  }
}

void _timezone(String value, String parent) {
  if (value.isEmpty) throw FormatException('$parent.timezone is required.');
}

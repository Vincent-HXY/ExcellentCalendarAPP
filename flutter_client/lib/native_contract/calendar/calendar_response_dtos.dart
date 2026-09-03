import '../shared/contract_value.dart';
import '../shared/native_json_normalizer.dart';
import 'calendar_civil_date.dart';
import 'calendar_contract_enums.dart';
import 'calendar_request_dtos.dart';

class CalendarRangeDaySummaryDto {
  const CalendarRangeDaySummaryDto({
    required this.date,
    required this.hasOpenEvent,
    required this.hasPendingHabit,
    required this.hasAnniversary,
  });

  final String date;
  final bool hasOpenEvent;
  final bool hasPendingHabit;
  final bool hasAnniversary;

  factory CalendarRangeDaySummaryDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarRangeDaySummary';
    ContractValue.requireExactKeys(json, const {
      'date',
      'has_open_event',
      'has_pending_habit',
      'has_anniversary',
    }, parent);
    return CalendarRangeDaySummaryDto(
      date: ContractValue.localDate(json, 'date', parent),
      hasOpenEvent: ContractValue.boolean(json, 'has_open_event', parent),
      hasPendingHabit: ContractValue.boolean(json, 'has_pending_habit', parent),
      hasAnniversary: ContractValue.boolean(json, 'has_anniversary', parent),
    );
  }
}

class CalendarRangeSummaryResponseDto {
  CalendarRangeSummaryResponseDto({
    required this.rangeStartDate,
    required this.rangeEndDate,
    required this.timezone,
    required this.snapshotToken,
    required List<CalendarRangeDaySummaryDto> days,
  }) : days = List.unmodifiable(days) {
    _validate();
  }

  final String rangeStartDate;
  final String rangeEndDate;
  final String timezone;
  final String snapshotToken;
  final List<CalendarRangeDaySummaryDto> days;

  factory CalendarRangeSummaryResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarRangeSummaryResponse';
    ContractValue.requireExactKeys(json, const {
      'range_start_date',
      'range_end_date',
      'timezone',
      'snapshot_token',
      'days',
    }, parent);
    final rawDays = json['days'];
    if (rawDays is! List || rawDays.isEmpty || rawDays.length > 42) {
      throw const FormatException(
        'CalendarRangeSummaryResponse.days must contain 1..42 items.',
      );
    }
    final timezone = ContractValue.nonEmptyString(json, 'timezone', parent);
    if (timezone.length > 255) {
      throw const FormatException(
        'CalendarRangeSummaryResponse.timezone is too long.',
      );
    }
    return CalendarRangeSummaryResponseDto(
      rangeStartDate: ContractValue.localDate(json, 'range_start_date', parent),
      rangeEndDate: ContractValue.localDate(json, 'range_end_date', parent),
      timezone: timezone,
      snapshotToken: _snapshotToken(json, 'snapshot_token', parent),
      days: rawDays
          .map(
            (item) => CalendarRangeDaySummaryDto.fromJson(
              NativeJsonNormalizer.normalizeMap(item),
            ),
          )
          .toList(growable: false),
    );
  }

  void _validate() {
    ContractValue.validateLocalDate(
      rangeStartDate,
      field: 'CalendarRangeSummaryResponse.range_start_date',
    );
    ContractValue.validateLocalDate(
      rangeEndDate,
      field: 'CalendarRangeSummaryResponse.range_end_date',
    );
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'CalendarRangeSummaryResponse.timezone must be 1..255 characters.',
      );
    }
    if (!isCalendarSnapshotToken(snapshotToken)) {
      throw const FormatException(
        'CalendarRangeSummaryResponse.snapshot_token is malformed.',
      );
    }
    final start = CalendarCivilDate.parse(
      rangeStartDate,
      field: 'CalendarRangeSummaryResponse.range_start_date',
    );
    final end = CalendarCivilDate.parse(
      rangeEndDate,
      field: 'CalendarRangeSummaryResponse.range_end_date',
    );
    final expectedCount = start.daysUntil(end);
    if (expectedCount < 1 ||
        expectedCount > 42 ||
        days.length != expectedCount) {
      throw const FormatException(
        'CalendarRangeSummaryResponse.days must exactly cover its range.',
      );
    }
    for (var index = 0; index < days.length; index++) {
      final expected = start.addDays(index).wireValue;
      if (days[index].date != expected) {
        throw const FormatException(
          'CalendarRangeSummaryResponse.days must be gap-free and ascending.',
        );
      }
    }
  }

  void validateAgainst(CalendarRangeSummaryRequestDto request) {
    if (rangeStartDate != request.rangeStartDate ||
        rangeEndDate != request.rangeEndDate ||
        timezone != request.timezone) {
      throw const FormatException(
        'CalendarRangeSummaryResponse does not match its request.',
      );
    }
  }

  CalendarRangeDaySummaryDto? summaryFor(String date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }
}

abstract class CalendarDayItemDto {
  const CalendarDayItemDto();
  String get identityKey;
}

class CalendarEventItemDto extends CalendarDayItemDto {
  CalendarEventItemDto({
    required this.eventId,
    required this.title,
    required this.isAllDay,
    required this.isRecurring,
    required this.recurrenceRevision,
    required this.occurrenceKey,
    required this.occurrenceStartAt,
    required this.occurrenceStartDate,
    required this.startAt,
    required this.endAt,
    required this.startDate,
    required this.endDate,
    required this.dayDisplay,
    required this.displayLocalTime,
    required this.status,
    required this.hasActiveReminder,
  }) {
    _validate();
  }

  final String eventId;
  final String title;
  final bool isAllDay;
  final bool isRecurring;
  final int? recurrenceRevision;
  final String? occurrenceKey;
  final DateTime? occurrenceStartAt;
  final String? occurrenceStartDate;
  final DateTime? startAt;
  final DateTime? endAt;
  final String? startDate;
  final String? endDate;
  final CalendarEventDayDisplay dayDisplay;
  final String? displayLocalTime;
  final CalendarEventItemStatus status;
  final bool hasActiveReminder;

  @override
  String get identityKey =>
      'event:$eventId:${recurrenceRevision ?? '-'}:${occurrenceKey ?? '-'}';

  factory CalendarEventItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarEventItem';
    ContractValue.requireExactKeys(json, const {
      'event_id',
      'title',
      'is_all_day',
      'is_recurring',
      'recurrence_revision',
      'occurrence_key',
      'occurrence_start_at',
      'occurrence_start_date',
      'start_at',
      'end_at',
      'start_date',
      'end_date',
      'day_display',
      'display_local_time',
      'status',
      'has_active_reminder',
    }, parent);
    final displayTime = ContractValue.optionalString(
      json,
      'display_local_time',
      parent,
    );
    if (displayTime != null &&
        !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(displayTime)) {
      throw const FormatException(
        'CalendarEventItem.display_local_time must use HH:mm.',
      );
    }
    return CalendarEventItemDto(
      eventId: ContractValue.uuid(json, 'event_id', parent),
      title: ContractValue.nonEmptyString(json, 'title', parent),
      isAllDay: ContractValue.boolean(json, 'is_all_day', parent),
      isRecurring: ContractValue.boolean(json, 'is_recurring', parent),
      recurrenceRevision: ContractValue.optionalInteger(
        json,
        'recurrence_revision',
        parent,
        minimum: 1,
      ),
      occurrenceKey: ContractValue.optionalUuid(json, 'occurrence_key', parent),
      occurrenceStartAt: ContractValue.optionalUtcDateTime(
        json,
        'occurrence_start_at',
        parent,
        wholeSecond: true,
      ),
      occurrenceStartDate: ContractValue.optionalLocalDate(
        json,
        'occurrence_start_date',
        parent,
      ),
      startAt: ContractValue.optionalUtcDateTime(
        json,
        'start_at',
        parent,
        wholeSecond: true,
      ),
      endAt: ContractValue.optionalUtcDateTime(
        json,
        'end_at',
        parent,
        wholeSecond: true,
      ),
      startDate: ContractValue.optionalLocalDate(json, 'start_date', parent),
      endDate: ContractValue.optionalLocalDate(json, 'end_date', parent),
      dayDisplay: CalendarEventDayDisplay.fromWireValue(
        ContractValue.nonEmptyString(json, 'day_display', parent),
      ),
      displayLocalTime: displayTime,
      status: CalendarEventItemStatus.fromWireValue(
        ContractValue.nonEmptyString(json, 'status', parent),
      ),
      hasActiveReminder: ContractValue.boolean(
        json,
        'has_active_reminder',
        parent,
      ),
    );
  }

  void _validate() {
    if (title.isEmpty) {
      throw const FormatException('CalendarEventItem.title is empty.');
    }
    if (isAllDay) {
      if (startAt != null ||
          endAt != null ||
          startDate == null ||
          endDate == null ||
          dayDisplay != CalendarEventDayDisplay.allDay ||
          displayLocalTime != null) {
        throw const FormatException(
          'CalendarEventItem all-day time structure is inconsistent.',
        );
      }
      final start = CalendarCivilDate.parse(
        startDate!,
        field: 'CalendarEventItem.start_date',
      );
      final end = CalendarCivilDate.parse(
        endDate!,
        field: 'CalendarEventItem.end_date',
      );
      if (!start.isBefore(end)) {
        throw const FormatException(
          'CalendarEventItem all-day start must be before end.',
        );
      }
    } else if (startAt == null ||
        endAt == null ||
        startDate != null ||
        endDate != null ||
        dayDisplay == CalendarEventDayDisplay.allDay) {
      throw const FormatException(
        'CalendarEventItem timed structure is inconsistent.',
      );
    } else if (!startAt!.isBefore(endAt!)) {
      throw const FormatException(
        'CalendarEventItem timed start must be before end.',
      );
    }
    final needsDisplayTime =
        dayDisplay == CalendarEventDayDisplay.startsAt ||
        dayDisplay == CalendarEventDayDisplay.endsAt;
    if (needsDisplayTime != (displayLocalTime != null)) {
      throw const FormatException(
        'CalendarEventItem display time does not match day_display.',
      );
    }
    if (isRecurring) {
      if (recurrenceRevision == null || occurrenceKey == null) {
        throw const FormatException(
          'CalendarEventItem recurring identity is incomplete.',
        );
      }
      if (isAllDay) {
        if (occurrenceStartDate == null || occurrenceStartAt != null) {
          throw const FormatException(
            'CalendarEventItem recurring all-day anchor is invalid.',
          );
        }
      } else if (occurrenceStartAt == null || occurrenceStartDate != null) {
        throw const FormatException(
          'CalendarEventItem recurring timed anchor is invalid.',
        );
      }
    } else if (recurrenceRevision != null ||
        occurrenceKey != null ||
        occurrenceStartAt != null ||
        occurrenceStartDate != null) {
      throw const FormatException(
        'CalendarEventItem non-recurring identity must be null.',
      );
    }
  }
}

class CalendarHabitItemDto extends CalendarDayItemDto {
  CalendarHabitItemDto({
    required this.habitId,
    required this.date,
    required this.title,
    required this.status,
    required this.checkInId,
    required this.completedCountHundredths,
    required this.targetCountHundredths,
    required this.unit,
    required this.hasActiveReminder,
  }) {
    _validate();
  }

  final String habitId;
  final String date;
  final String title;
  final CalendarHabitItemStatus status;
  final String? checkInId;
  final int? completedCountHundredths;
  final int? targetCountHundredths;
  final String? unit;
  final bool hasActiveReminder;

  @override
  String get identityKey => 'habit:$habitId';

  factory CalendarHabitItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarHabitItem';
    ContractValue.requireExactKeys(json, const {
      'habit_id',
      'date',
      'title',
      'status',
      'check_in_id',
      'completed_count_hundredths',
      'target_count_hundredths',
      'unit',
      'has_active_reminder',
    }, parent);
    final title = ContractValue.nonEmptyString(json, 'title', parent);
    final unit = ContractValue.optionalString(json, 'unit', parent);
    if (title.runes.length > 80 ||
        unit != null && (unit.isEmpty || unit.runes.length > 32)) {
      throw const FormatException(
        'CalendarHabitItem title or unit length is invalid.',
      );
    }
    return CalendarHabitItemDto(
      habitId: ContractValue.uuid(json, 'habit_id', parent),
      date: ContractValue.localDate(json, 'date', parent),
      title: title,
      status: CalendarHabitItemStatus.fromWireValue(
        ContractValue.nonEmptyString(json, 'status', parent),
      ),
      checkInId: ContractValue.optionalUuid(json, 'check_in_id', parent),
      completedCountHundredths: ContractValue.optionalInteger(
        json,
        'completed_count_hundredths',
        parent,
        minimum: 1,
        maximum: 9007199254740991,
      ),
      targetCountHundredths: ContractValue.optionalInteger(
        json,
        'target_count_hundredths',
        parent,
        minimum: 1,
        maximum: 9007199254740991,
      ),
      unit: unit,
      hasActiveReminder: ContractValue.boolean(
        json,
        'has_active_reminder',
        parent,
      ),
    );
  }

  void _validate() {
    final hasTarget = targetCountHundredths != null;
    if (hasTarget != (unit != null)) {
      throw const FormatException(
        'CalendarHabitItem target and unit must both be null or present.',
      );
    }
    switch (status) {
      case CalendarHabitItemStatus.upcoming ||
          CalendarHabitItemStatus.absent ||
          CalendarHabitItemStatus.missed:
        if (checkInId != null || completedCountHundredths != null) {
          throw const FormatException(
            'CalendarHabitItem derived status cannot contain a check-in.',
          );
        }
      case CalendarHabitItemStatus.partial:
        if (checkInId == null ||
            completedCountHundredths == null ||
            targetCountHundredths == null ||
            unit == null) {
          throw const FormatException(
            'CalendarHabitItem partial progress is incomplete.',
          );
        }
        if (completedCountHundredths! <= 0 ||
            targetCountHundredths! <= 0 ||
            completedCountHundredths! >= targetCountHundredths!) {
          throw const FormatException(
            'CalendarHabitItem partial progress must be below target.',
          );
        }
      case CalendarHabitItemStatus.done:
        if (checkInId == null ||
            (completedCountHundredths == null) !=
                (targetCountHundredths == null)) {
          throw const FormatException(
            'CalendarHabitItem done progress is inconsistent.',
          );
        }
        if (completedCountHundredths != null &&
            (completedCountHundredths! <= 0 ||
                targetCountHundredths! <= 0 ||
                completedCountHundredths! < targetCountHundredths!)) {
          throw const FormatException(
            'CalendarHabitItem done progress must reach target.',
          );
        }
      case CalendarHabitItemStatus.skipped:
        if (checkInId == null || completedCountHundredths != null) {
          throw const FormatException(
            'CalendarHabitItem skipped state is inconsistent.',
          );
        }
    }
  }
}

class CalendarAnniversaryItemDto extends CalendarDayItemDto {
  CalendarAnniversaryItemDto({
    required this.anniversaryId,
    required this.occurrenceKey,
    required this.occurrenceDate,
    required this.sourceDate,
    required this.title,
    required this.isRepeating,
    required this.yearsElapsed,
    required this.importance,
    required this.hasActiveReminder,
  }) {
    if (!isRepeating && yearsElapsed != 0) {
      throw const FormatException(
        'A one-time CalendarAnniversaryItem must have years_elapsed=0.',
      );
    }
  }

  final String anniversaryId;
  final String occurrenceKey;
  final String occurrenceDate;
  final String sourceDate;
  final String title;
  final bool isRepeating;
  final int yearsElapsed;
  final CalendarAnniversaryImportance? importance;
  final bool hasActiveReminder;

  @override
  String get identityKey => 'anniversary:$occurrenceKey';

  factory CalendarAnniversaryItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarAnniversaryItem';
    ContractValue.requireExactKeys(json, const {
      'anniversary_id',
      'occurrence_key',
      'occurrence_date',
      'source_date',
      'title',
      'is_repeating',
      'years_elapsed',
      'importance',
      'has_active_reminder',
    }, parent);
    final rawImportance = json['importance'];
    if (rawImportance != null && rawImportance is! String) {
      throw const FormatException(
        'CalendarAnniversaryItem.importance must be string or null.',
      );
    }
    return CalendarAnniversaryItemDto(
      anniversaryId: ContractValue.uuid(json, 'anniversary_id', parent),
      occurrenceKey: ContractValue.uuid(json, 'occurrence_key', parent),
      occurrenceDate: ContractValue.localDate(json, 'occurrence_date', parent),
      sourceDate: ContractValue.localDate(json, 'source_date', parent),
      title: ContractValue.nonEmptyString(json, 'title', parent),
      isRepeating: ContractValue.boolean(json, 'is_repeating', parent),
      yearsElapsed: ContractValue.integer(
        json,
        'years_elapsed',
        parent,
        minimum: 0,
      ),
      importance: CalendarAnniversaryImportance.fromNullableWireValue(
        rawImportance as String?,
      ),
      hasActiveReminder: ContractValue.boolean(
        json,
        'has_active_reminder',
        parent,
      ),
    );
  }
}

class CalendarDayItemPageDto {
  CalendarDayItemPageDto({
    required this.date,
    required this.timezone,
    required this.section,
    required this.snapshotToken,
    required this.pageSize,
    required List<CalendarDayItemDto> items,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items) {
    _validate();
  }

  final String date;
  final String timezone;
  final CalendarSection section;
  final String snapshotToken;
  final int pageSize;
  final List<CalendarDayItemDto> items;
  final bool hasMore;
  final String? nextCursor;

  factory CalendarDayItemPageDto.fromJson(Map<String, dynamic> json) {
    const parent = 'CalendarDayItemPage';
    ContractValue.requireExactKeys(json, const {
      'date',
      'timezone',
      'section',
      'snapshot_token',
      'page_size',
      'items',
      'has_more',
      'next_cursor',
    }, parent);
    final section = CalendarSection.fromWireValue(
      ContractValue.nonEmptyString(json, 'section', parent),
    );
    final rawItems = json['items'];
    if (rawItems is! List || rawItems.length > 100) {
      throw const FormatException(
        'CalendarDayItemPage.items must contain at most 100 items.',
      );
    }
    final rawNextCursor = json['next_cursor'];
    if (rawNextCursor != null && rawNextCursor is! String) {
      throw const FormatException(
        'CalendarDayItemPage.next_cursor must be string or null.',
      );
    }
    return CalendarDayItemPageDto(
      date: ContractValue.localDate(json, 'date', parent),
      timezone: ContractValue.nonEmptyString(json, 'timezone', parent),
      section: section,
      snapshotToken: _snapshotToken(json, 'snapshot_token', parent),
      pageSize: ContractValue.integer(
        json,
        'page_size',
        parent,
        minimum: 1,
        maximum: 100,
      ),
      items: rawItems
          .map(
            (item) =>
                _parseItem(section, NativeJsonNormalizer.normalizeMap(item)),
          )
          .toList(growable: false),
      hasMore: ContractValue.boolean(json, 'has_more', parent),
      nextCursor: rawNextCursor as String?,
    );
  }

  void _validate() {
    ContractValue.validateLocalDate(date, field: 'CalendarDayItemPage.date');
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'CalendarDayItemPage.timezone must be 1..255 characters.',
      );
    }
    if (!isCalendarSnapshotToken(snapshotToken)) {
      throw const FormatException(
        'CalendarDayItemPage.snapshot_token is malformed.',
      );
    }
    if (pageSize < 1 || pageSize > 100 || items.length > pageSize) {
      throw const FormatException(
        'CalendarDayItemPage page size or item count is invalid.',
      );
    }
    if (hasMore) {
      if (items.isEmpty ||
          nextCursor == null ||
          !isCalendarCursor(nextCursor!)) {
        throw const FormatException(
          'A non-terminal CalendarDayItemPage needs items and a cursor.',
        );
      }
    } else if (nextCursor != null) {
      throw const FormatException(
        'A terminal CalendarDayItemPage must have next_cursor=null.',
      );
    }
    final identities = <String>{};
    for (final item in items) {
      if (!identities.add(item.identityKey)) {
        throw const FormatException(
          'CalendarDayItemPage contains a duplicate item identity.',
        );
      }
      if (item is CalendarHabitItemDto && item.date != date ||
          item is CalendarAnniversaryItemDto && item.occurrenceDate != date) {
        throw const FormatException(
          'CalendarDayItemPage item date does not match the page date.',
        );
      }
      final matchesSection = switch (section) {
        CalendarSection.event => item is CalendarEventItemDto,
        CalendarSection.habit => item is CalendarHabitItemDto,
        CalendarSection.anniversary => item is CalendarAnniversaryItemDto,
      };
      if (!matchesSection) {
        throw const FormatException(
          'CalendarDayItemPage item type does not match section.',
        );
      }
    }
  }

  void validateAgainst(CalendarListDayItemsRequestDto request) {
    if (date != request.date ||
        timezone != request.timezone ||
        section != request.section ||
        snapshotToken != request.snapshotToken ||
        pageSize != request.pageSize ||
        request.cursor != null && nextCursor == request.cursor) {
      throw const FormatException(
        'CalendarDayItemPage does not match its request or cursor did not advance.',
      );
    }
  }
}

CalendarDayItemDto _parseItem(
  CalendarSection section,
  Map<String, dynamic> json,
) => switch (section) {
  CalendarSection.event => CalendarEventItemDto.fromJson(json),
  CalendarSection.habit => CalendarHabitItemDto.fromJson(json),
  CalendarSection.anniversary => CalendarAnniversaryItemDto.fromJson(json),
};

String _snapshotToken(Map<String, dynamic> json, String key, String parent) {
  final value = ContractValue.nonEmptyString(json, key, parent);
  if (!isCalendarSnapshotToken(value)) {
    throw FormatException('$parent.$key is malformed.');
  }
  return value;
}

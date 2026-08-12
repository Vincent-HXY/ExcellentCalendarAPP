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
  });

  final String title;
  final DateTime date;
  final AnniversaryCalendarTypeContract calendarType;
  final String? categoryId;
  final AnniversaryRecurrenceRuleInputDto? recurrence;
  final String? note;
  final AnniversaryImportanceContract importance;
  final String timezone;

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
    };
  }
}

class UpdateAnniversaryRequestDto {
  const UpdateAnniversaryRequestDto({
    required this.id,
    required this.title,
    required this.date,
    required this.calendarType,
    required this.categoryId,
    required this.recurrence,
    required this.note,
    required this.importance,
    required this.timezone,
  });

  final String id;
  final String title;
  final DateTime date;
  final AnniversaryCalendarTypeContract calendarType;
  final String? categoryId;
  final AnniversaryRecurrenceRuleInputDto? recurrence;
  final String? note;
  final AnniversaryImportanceContract importance;
  final String timezone;

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
      'title': title,
      'date': AnniversaryRequestValue.localDate(date),
      'calendar_type': calendarType.wireValue,
      'category_id': categoryId,
      'recurrence': recurrence?.toJson(),
      'note': note,
      'importance': importance.wireValue,
      'timezone': timezone,
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
}

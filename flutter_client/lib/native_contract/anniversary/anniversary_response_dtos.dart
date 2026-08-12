import '../common/pagination_response_dto.dart';
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

class AnniversaryDetailResponseDto {
  const AnniversaryDetailResponseDto({
    required this.anniversary,
    required this.recurrence,
    required this.countdown,
  });

  final AnniversaryResponseDto anniversary;
  final AnniversaryRecurrenceResponseDto? recurrence;
  final AnniversaryCountdownResponseDto countdown;

  factory AnniversaryDetailResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'anniversary',
      'recurrence',
      'countdown',
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

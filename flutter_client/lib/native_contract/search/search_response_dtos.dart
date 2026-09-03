import '../shared/contract_value.dart';
import '../shared/native_json_normalizer.dart';
import 'search_contract_enums.dart';
import 'search_text_contract.dart';

const _maxSafeInteger = 9007199254740991;
final RegExp _snapshotPattern = RegExp(r'^srchsnap1\.[A-Za-z0-9_-]{20,512}$');
final RegExp _cursorPattern = RegExp(r'^srchcur1\.[A-Za-z0-9_-]{20,2048}$');

class SearchSnippetDto {
  const SearchSnippetDto({
    required this.field,
    required this.text,
    required this.prefixTruncated,
    required this.suffixTruncated,
  });
  final SearchMatchedField field;
  final String text;
  final bool prefixTruncated;
  final bool suffixTruncated;

  factory SearchSnippetDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchSnippet';
    ContractValue.requireExactKeys(json, const {
      'field',
      'text',
      'prefix_truncated',
      'suffix_truncated',
    }, parent);
    final field = SearchMatchedField.fromWireValue(
      ContractValue.nonEmptyString(json, 'field', parent),
    );
    if (field == SearchMatchedField.title) {
      throw const FormatException('Search snippet cannot use the title field.');
    }
    final text = ContractValue.nonEmptyString(json, 'text', parent);
    if (SearchTextContract.analyze(text).scalarCount > 200) {
      throw const FormatException('Search snippet is too long.');
    }
    return SearchSnippetDto(
      field: field,
      text: text,
      prefixTruncated: ContractValue.boolean(json, 'prefix_truncated', parent),
      suffixTruncated: ContractValue.boolean(json, 'suffix_truncated', parent),
    );
  }
}

class SearchMatchDto {
  const SearchMatchDto({
    required this.primaryField,
    required this.matchedFields,
    required this.snippet,
  });
  final SearchMatchedField primaryField;
  final List<SearchMatchedField> matchedFields;
  final SearchSnippetDto? snippet;

  factory SearchMatchDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchMatch';
    ContractValue.requireExactKeys(json, const {
      'primary_field',
      'matched_fields',
      'snippet',
    }, parent);
    final primary = SearchMatchedField.fromWireValue(
      ContractValue.nonEmptyString(json, 'primary_field', parent),
    );
    final rawFields = json['matched_fields'];
    if (rawFields is! List || rawFields.isEmpty || rawFields.length > 4) {
      throw const FormatException(
        'Search matched_fields must contain 1..4 items.',
      );
    }
    final fields = rawFields
        .map((raw) {
          if (raw is! String) {
            throw const FormatException('Search matched field must be string.');
          }
          return SearchMatchedField.fromWireValue(raw);
        })
        .toList(growable: false);
    if (fields.toSet().length != fields.length || !fields.contains(primary)) {
      throw const FormatException('Search matched_fields are inconsistent.');
    }
    final rawSnippet = json['snippet'];
    final snippet = rawSnippet == null
        ? null
        : SearchSnippetDto.fromJson(
            NativeJsonNormalizer.normalizeMap(rawSnippet),
          );
    if ((primary == SearchMatchedField.title) != (snippet == null)) {
      throw const FormatException(
        'Search primary field and snippet are inconsistent.',
      );
    }
    return SearchMatchDto(
      primaryField: primary,
      matchedFields: List.unmodifiable(fields),
      snippet: snippet,
    );
  }
}

class SearchCategoryDto {
  const SearchCategoryDto({
    required this.id,
    required this.name,
    this.color,
    this.icon,
  });
  final String id;
  final String name;
  final String? color;
  final String? icon;

  factory SearchCategoryDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchCategory';
    ContractValue.requireExactKeys(json, const {
      'id',
      'name',
      'color',
      'icon',
    }, parent);
    final name = ContractValue.nonEmptyString(json, 'name', parent);
    final color = ContractValue.optionalString(json, 'color', parent);
    final icon = ContractValue.optionalString(json, 'icon', parent);
    final id = ContractValue.uuid(json, 'id', parent);
    if (SearchTextContract.analyze(name).scalarCount > 40 ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        (color != null && !RegExp(r'^#[0-9A-F]{6}$').hasMatch(color)) ||
        (icon != null &&
            (icon.isEmpty ||
                SearchTextContract.analyze(icon).scalarCount > 64))) {
      throw const FormatException('Search category projection is invalid.');
    }
    return SearchCategoryDto(id: id, name: name, color: color, icon: icon);
  }
}

sealed class SearchItemDto {
  const SearchItemDto({
    required this.targetType,
    required this.targetId,
    required this.title,
    required this.match,
    required this.category,
    required this.updatedAt,
  });
  final SearchTargetType targetType;
  final String targetId;
  final String title;
  final SearchMatchDto match;
  final SearchCategoryDto? category;
  final DateTime updatedAt;
  String get identityKey => '${targetType.wireValue}:$targetId';
}

class SearchEventItemDto extends SearchItemDto {
  const SearchEventItemDto({
    required super.targetId,
    required super.title,
    required super.match,
    required super.category,
    required super.updatedAt,
    required this.status,
    required this.isAllDay,
    required this.isRecurring,
    required this.occurAt,
    required this.occurDate,
    required this.location,
    required this.recurrenceRevision,
    required this.occurrenceKey,
  }) : super(targetType: SearchTargetType.event);
  final SearchEventStatus status;
  final bool isAllDay;
  final bool isRecurring;
  final DateTime? occurAt;
  final String? occurDate;
  final String? location;
  final int? recurrenceRevision;
  final String? occurrenceKey;

  factory SearchEventItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchEventItem';
    ContractValue.requireExactKeys(json, const {
      'target_type',
      'target_id',
      'title',
      'match',
      'category',
      'updated_at',
      'status',
      'is_all_day',
      'is_recurring',
      'occur_at',
      'occur_date',
      'location',
      'recurrence_revision',
      'occurrence_key',
    }, parent);
    _requireTarget(json, parent, SearchTargetType.event);
    final common = _CommonItem.parse(json, parent);
    final isAllDay = ContractValue.boolean(json, 'is_all_day', parent);
    final isRecurring = ContractValue.boolean(json, 'is_recurring', parent);
    final occurAt = ContractValue.optionalUtcDateTime(
      json,
      'occur_at',
      parent,
      wholeSecond: true,
    );
    final occurDate = ContractValue.optionalLocalDate(
      json,
      'occur_date',
      parent,
    );
    final revision = ContractValue.optionalInteger(
      json,
      'recurrence_revision',
      parent,
      minimum: 1,
    );
    final occurrenceKey = ContractValue.optionalUuid(
      json,
      'occurrence_key',
      parent,
    );
    if (isAllDay
        ? occurAt != null || occurDate == null
        : occurAt == null || occurDate != null) {
      throw const FormatException(
        'Search event occurrence time union is invalid.',
      );
    }
    if (isRecurring
        ? revision == null || occurrenceKey == null
        : revision != null || occurrenceKey != null) {
      throw const FormatException(
        'Search event recurrence identity is invalid.',
      );
    }
    return SearchEventItemDto(
      targetId: common.id,
      title: common.title,
      match: common.match,
      category: common.category,
      updatedAt: common.updatedAt,
      status: SearchEventStatus.fromWireValue(
        ContractValue.nonEmptyString(json, 'status', parent),
      ),
      isAllDay: isAllDay,
      isRecurring: isRecurring,
      occurAt: occurAt,
      occurDate: occurDate,
      location: ContractValue.optionalString(json, 'location', parent),
      recurrenceRevision: revision,
      occurrenceKey: occurrenceKey,
    );
  }
}

class SearchHabitItemDto extends SearchItemDto {
  const SearchHabitItemDto({
    required super.targetId,
    required super.title,
    required super.match,
    required super.category,
    required super.updatedAt,
    required this.lifecycleStatus,
    required this.occurDate,
    required this.challengeStartDate,
    required this.challengeEndDate,
    required this.endedDate,
    required this.remainingDays,
    required this.targetCountHundredths,
    required this.unit,
  }) : super(targetType: SearchTargetType.habit);
  final SearchHabitLifecycle lifecycleStatus;
  final String occurDate;
  final String challengeStartDate;
  final String challengeEndDate;
  final String? endedDate;
  final int remainingDays;
  final int? targetCountHundredths;
  final String? unit;

  factory SearchHabitItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchHabitItem';
    ContractValue.requireExactKeys(json, const {
      'target_type',
      'target_id',
      'title',
      'match',
      'category',
      'updated_at',
      'lifecycle_status',
      'occur_date',
      'challenge_start_date',
      'challenge_end_date',
      'ended_date',
      'remaining_days',
      'target_count_hundredths',
      'unit',
    }, parent);
    _requireTarget(json, parent, SearchTargetType.habit);
    final common = _CommonItem.parse(json, parent);
    final lifecycle = SearchHabitLifecycle.fromWireValue(
      ContractValue.nonEmptyString(json, 'lifecycle_status', parent),
    );
    final count = ContractValue.optionalInteger(
      json,
      'target_count_hundredths',
      parent,
      minimum: 1,
      maximum: _maxSafeInteger,
    );
    final unit = ContractValue.optionalString(json, 'unit', parent);
    if ((count == null) != (unit == null) ||
        (unit != null &&
            (unit.isEmpty ||
                SearchTextContract.analyze(unit).scalarCount > 32))) {
      throw const FormatException('Search habit target union is invalid.');
    }
    final remaining = ContractValue.integer(
      json,
      'remaining_days',
      parent,
      minimum: 0,
      maximum: 400,
    );
    if ({
          SearchHabitLifecycle.completed,
          SearchHabitLifecycle.endedEarly,
        }.contains(lifecycle) &&
        remaining != 0) {
      throw const FormatException(
        'Ended Search habit must have zero remaining days.',
      );
    }
    return SearchHabitItemDto(
      targetId: common.id,
      title: common.title,
      match: common.match,
      category: common.category,
      updatedAt: common.updatedAt,
      lifecycleStatus: lifecycle,
      occurDate: ContractValue.localDate(json, 'occur_date', parent),
      challengeStartDate: ContractValue.localDate(
        json,
        'challenge_start_date',
        parent,
      ),
      challengeEndDate: ContractValue.localDate(
        json,
        'challenge_end_date',
        parent,
      ),
      endedDate: ContractValue.optionalLocalDate(json, 'ended_date', parent),
      remainingDays: remaining,
      targetCountHundredths: count,
      unit: unit,
    );
  }
}

class SearchAnniversaryItemDto extends SearchItemDto {
  const SearchAnniversaryItemDto({
    required super.targetId,
    required super.title,
    required super.match,
    required super.category,
    required super.updatedAt,
    required this.occurrenceKey,
    required this.occurDate,
    required this.sourceDate,
    required this.isRepeating,
    required this.relation,
    required this.days,
    required this.yearsElapsed,
  }) : super(targetType: SearchTargetType.anniversary);
  final String occurrenceKey;
  final String occurDate;
  final String sourceDate;
  final bool isRepeating;
  final SearchAnniversaryRelation relation;
  final int days;
  final int yearsElapsed;

  factory SearchAnniversaryItemDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchAnniversaryItem';
    ContractValue.requireExactKeys(json, const {
      'target_type',
      'target_id',
      'title',
      'match',
      'category',
      'updated_at',
      'occurrence_key',
      'occur_date',
      'source_date',
      'is_repeating',
      'relation',
      'days',
      'years_elapsed',
    }, parent);
    _requireTarget(json, parent, SearchTargetType.anniversary);
    final common = _CommonItem.parse(json, parent);
    final repeating = ContractValue.boolean(json, 'is_repeating', parent);
    final relation = SearchAnniversaryRelation.fromWireValue(
      ContractValue.nonEmptyString(json, 'relation', parent),
    );
    final days = ContractValue.integer(json, 'days', parent, minimum: 0);
    final years = ContractValue.integer(
      json,
      'years_elapsed',
      parent,
      minimum: 0,
    );
    if ((relation == SearchAnniversaryRelation.today) != (days == 0) ||
        (!repeating && years != 0)) {
      throw const FormatException('Search anniversary projection is invalid.');
    }
    return SearchAnniversaryItemDto(
      targetId: common.id,
      title: common.title,
      match: common.match,
      category: common.category,
      updatedAt: common.updatedAt,
      occurrenceKey: ContractValue.uuid(json, 'occurrence_key', parent),
      occurDate: ContractValue.localDate(json, 'occur_date', parent),
      sourceDate: ContractValue.localDate(json, 'source_date', parent),
      isRepeating: repeating,
      relation: relation,
      days: days,
      yearsElapsed: years,
    );
  }
}

class SearchSectionResponseDto {
  SearchSectionResponseDto({
    required this.targetType,
    required List<SearchItemDto> items,
    required this.totalCount,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items) {
    if (items.length > 20 ||
        items.any((item) => item.targetType != targetType) ||
        items.map((item) => item.identityKey).toSet().length != items.length ||
        totalCount < items.length ||
        totalCount > _maxSafeInteger ||
        (hasMore ? items.isEmpty || nextCursor == null : nextCursor != null) ||
        (nextCursor != null && !_isCursor(nextCursor!))) {
      throw const FormatException('Search section response is inconsistent.');
    }
  }
  final SearchTargetType targetType;
  final List<SearchItemDto> items;
  final int totalCount;
  final bool hasMore;
  final String? nextCursor;

  factory SearchSectionResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchSectionResponse';
    ContractValue.requireExactKeys(json, const {
      'target_type',
      'items',
      'total_count',
      'has_more',
      'next_cursor',
    }, parent);
    final type = SearchTargetType.fromWireValue(
      ContractValue.nonEmptyString(json, 'target_type', parent),
    );
    final rawItems = json['items'];
    if (rawItems is! List || rawItems.length > 20) {
      throw const FormatException('Search section items are invalid.');
    }
    final items = rawItems
        .map((raw) {
          final item = NativeJsonNormalizer.normalizeMap(raw);
          return switch (type) {
            SearchTargetType.event => SearchEventItemDto.fromJson(item),
            SearchTargetType.habit => SearchHabitItemDto.fromJson(item),
            SearchTargetType.anniversary => SearchAnniversaryItemDto.fromJson(
              item,
            ),
          };
        })
        .toList(growable: false);
    return SearchSectionResponseDto(
      targetType: type,
      items: items,
      totalCount: ContractValue.integer(
        json,
        'total_count',
        parent,
        minimum: 0,
        maximum: _maxSafeInteger,
      ),
      hasMore: ContractValue.boolean(json, 'has_more', parent),
      nextCursor: ContractValue.optionalString(json, 'next_cursor', parent),
    );
  }
}

class SearchQueryResponseDto {
  SearchQueryResponseDto({
    required this.queryGeneration,
    required this.normalizedKeyword,
    required this.timezone,
    required this.evaluatedAt,
    required this.snapshotToken,
    required List<SearchSectionResponseDto> sections,
  }) : sections = List.unmodifiable(sections) {
    final keywordAnalysis = SearchTextContract.analyze(normalizedKeyword);
    if (queryGeneration < 0 ||
        queryGeneration > _maxSafeInteger ||
        keywordAnalysis.normalizedDisplay.isEmpty ||
        normalizedKeyword != keywordAnalysis.normalizedDisplay ||
        keywordAnalysis.scalarCount >
            SearchTextContract.maximumKeywordScalars ||
        keywordAnalysis.utf8Bytes >
            SearchTextContract.maximumKeywordUtf8Bytes ||
        timezone.isEmpty ||
        timezone.length > 255 ||
        !_isSnapshot(snapshotToken) ||
        sections.isEmpty ||
        sections.length > 3 ||
        sections.map((section) => section.targetType).toSet().length !=
            sections.length) {
      throw const FormatException('Search query response is invalid.');
    }
  }
  final int queryGeneration;
  final String normalizedKeyword;
  final String timezone;
  final DateTime evaluatedAt;
  final String snapshotToken;
  final List<SearchSectionResponseDto> sections;

  factory SearchQueryResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchQueryResponse';
    ContractValue.requireExactKeys(json, const {
      'query_generation',
      'normalized_keyword',
      'timezone',
      'evaluated_at',
      'snapshot_token',
      'sections',
    }, parent);
    final rawSections = json['sections'];
    if (rawSections is! List || rawSections.isEmpty || rawSections.length > 3) {
      throw const FormatException('Search response sections are invalid.');
    }
    return SearchQueryResponseDto(
      queryGeneration: ContractValue.integer(
        json,
        'query_generation',
        parent,
        minimum: 0,
        maximum: _maxSafeInteger,
      ),
      normalizedKeyword: ContractValue.nonEmptyString(
        json,
        'normalized_keyword',
        parent,
      ),
      timezone: ContractValue.nonEmptyString(json, 'timezone', parent),
      evaluatedAt: ContractValue.utcDateTime(
        json,
        'evaluated_at',
        parent,
        wholeSecond: true,
      ),
      snapshotToken: ContractValue.nonEmptyString(
        json,
        'snapshot_token',
        parent,
      ),
      sections: rawSections
          .map(
            (raw) => SearchSectionResponseDto.fromJson(
              NativeJsonNormalizer.normalizeMap(raw),
            ),
          )
          .toList(growable: false),
    );
  }
}

class SearchHistoryResponseDto {
  SearchHistoryResponseDto({
    required this.revision,
    required List<String> items,
  }) : items = List.unmodifiable(items) {
    if (revision < 0 ||
        revision > _maxSafeInteger ||
        items.length > 20 ||
        !_validHistoryItems(items)) {
      throw const FormatException('Search history response is invalid.');
    }
  }
  final int revision;
  final List<String> items;

  factory SearchHistoryResponseDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchHistoryResponse';
    ContractValue.requireExactKeys(json, const {'revision', 'items'}, parent);
    return SearchHistoryResponseDto(
      revision: ContractValue.integer(
        json,
        'revision',
        parent,
        minimum: 0,
        maximum: _maxSafeInteger,
      ),
      items: ContractValue.stringList(json, 'items', parent, unique: true),
    );
  }
}

class _CommonItem {
  const _CommonItem(
    this.id,
    this.title,
    this.match,
    this.category,
    this.updatedAt,
  );
  final String id;
  final String title;
  final SearchMatchDto match;
  final SearchCategoryDto? category;
  final DateTime updatedAt;

  static _CommonItem parse(Map<String, dynamic> json, String parent) {
    final rawCategory = json['category'];
    final match = SearchMatchDto.fromJson(
      NativeJsonNormalizer.normalizeMap(json['match']),
    );
    final category = rawCategory == null
        ? null
        : SearchCategoryDto.fromJson(
            NativeJsonNormalizer.normalizeMap(rawCategory),
          );
    if (match.matchedFields.contains(SearchMatchedField.categoryName) &&
        category == null) {
      throw const FormatException(
        'Category-name match requires a current Category projection.',
      );
    }
    return _CommonItem(
      ContractValue.uuid(json, 'target_id', parent),
      ContractValue.nonEmptyString(json, 'title', parent),
      match,
      category,
      ContractValue.utcDateTime(json, 'updated_at', parent, wholeSecond: true),
    );
  }
}

void _requireTarget(
  Map<String, dynamic> json,
  String parent,
  SearchTargetType expected,
) {
  final target = SearchTargetType.fromWireValue(
    ContractValue.nonEmptyString(json, 'target_type', parent),
  );
  if (target != expected) {
    throw FormatException('$parent.target_type is inconsistent.');
  }
}

bool _isCursor(String value) =>
    value.length <= 2057 && _cursorPattern.hasMatch(value);
bool _isSnapshot(String value) =>
    value.length <= 522 && _snapshotPattern.hasMatch(value);

bool _validHistoryItems(List<String> values) {
  try {
    final keys = <String>{};
    for (final value in values) {
      final analysis = SearchTextContract.analyze(value);
      if (analysis.normalizedDisplay.isEmpty ||
          value != analysis.normalizedDisplay ||
          analysis.scalarCount > SearchTextContract.maximumKeywordScalars ||
          analysis.utf8Bytes > SearchTextContract.maximumKeywordUtf8Bytes ||
          !keys.add(analysis.comparisonKey)) {
        return false;
      }
    }
    return true;
  } on FormatException {
    return false;
  }
}

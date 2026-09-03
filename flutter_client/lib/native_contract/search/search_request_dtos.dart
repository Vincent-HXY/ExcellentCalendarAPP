import '../shared/contract_value.dart';
import '../shared/native_json_normalizer.dart';
import 'search_contract_enums.dart';
import 'search_text_contract.dart';

const searchPageSize = 20;
const _maxSafeInteger = 9007199254740991;
final RegExp _searchCursorPattern = RegExp(
  r'^srchcur1\.[A-Za-z0-9_-]{20,2048}$',
);

class SearchSectionRequestDto {
  SearchSectionRequestDto({
    required this.targetType,
    required this.cursor,
    this.pageSize = searchPageSize,
  }) {
    if (pageSize != searchPageSize) {
      throw const FormatException('Search section page_size must be 20.');
    }
    final value = cursor;
    if (value != null &&
        (value.length > 2057 || !_searchCursorPattern.hasMatch(value))) {
      throw const FormatException('Search section cursor is malformed.');
    }
  }

  final SearchTargetType targetType;
  final int pageSize;
  final String? cursor;

  factory SearchSectionRequestDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchSectionRequest';
    ContractValue.requireExactKeys(json, const {
      'target_type',
      'page_size',
      'cursor',
    }, parent);
    return SearchSectionRequestDto(
      targetType: SearchTargetType.fromWireValue(
        ContractValue.nonEmptyString(json, 'target_type', parent),
      ),
      pageSize: ContractValue.integer(json, 'page_size', parent),
      cursor: ContractValue.optionalString(json, 'cursor', parent),
    );
  }

  Map<String, dynamic> toJson() => {
    'target_type': targetType.wireValue,
    'page_size': pageSize,
    'cursor': cursor,
  };
}

class SearchQueryRequestDto {
  SearchQueryRequestDto({
    required this.queryGeneration,
    required this.keyword,
    required this.timezone,
    required List<SearchTargetType> targetTypes,
    required this.dateFrom,
    required this.dateToExclusive,
    required List<String>? categoryIds,
    required this.includeUncategorized,
    required this.includeCompleted,
    required this.sortBy,
    required List<SearchSectionRequestDto> sections,
  }) : targetTypes = List.unmodifiable(targetTypes),
       categoryIds = categoryIds == null
           ? null
           : List.unmodifiable(categoryIds),
       sections = List.unmodifiable(sections) {
    _validate();
  }

  final int queryGeneration;
  final String keyword;
  final String timezone;
  final List<SearchTargetType> targetTypes;
  final String? dateFrom;
  final String? dateToExclusive;
  final List<String>? categoryIds;
  final bool includeUncategorized;
  final bool includeCompleted;
  final SearchSortBy sortBy;
  final List<SearchSectionRequestDto> sections;

  factory SearchQueryRequestDto.fromJson(Map<String, dynamic> json) {
    const parent = 'SearchQueryRequest';
    ContractValue.requireExactKeys(json, const {
      'query_generation',
      'keyword',
      'timezone',
      'target_types',
      'date_from',
      'date_to_exclusive',
      'category_ids',
      'include_uncategorized',
      'include_completed',
      'sort_by',
      'sections',
    }, parent);
    final rawCategories = json['category_ids'];
    if (rawCategories != null && rawCategories is! List) {
      throw const FormatException('Search category_ids must be array or null.');
    }
    final rawSections = json['sections'];
    if (rawSections is! List) {
      throw const FormatException('Search sections must be an array.');
    }
    return SearchQueryRequestDto(
      queryGeneration: ContractValue.integer(
        json,
        'query_generation',
        parent,
        minimum: 0,
        maximum: _maxSafeInteger,
      ),
      keyword: ContractValue.nonEmptyString(json, 'keyword', parent),
      timezone: ContractValue.nonEmptyString(json, 'timezone', parent),
      targetTypes: ContractValue.stringList(
        json,
        'target_types',
        parent,
        unique: true,
        nonEmpty: true,
      ).map(SearchTargetType.fromWireValue).toList(growable: false),
      dateFrom: ContractValue.optionalLocalDate(json, 'date_from', parent),
      dateToExclusive: ContractValue.optionalLocalDate(
        json,
        'date_to_exclusive',
        parent,
      ),
      categoryIds: _stringListOrNull(rawCategories),
      includeUncategorized: ContractValue.boolean(
        json,
        'include_uncategorized',
        parent,
      ),
      includeCompleted: ContractValue.boolean(
        json,
        'include_completed',
        parent,
      ),
      sortBy: SearchSortBy.fromWireValue(
        ContractValue.nonEmptyString(json, 'sort_by', parent),
      ),
      sections: rawSections
          .map(
            (raw) => SearchSectionRequestDto.fromJson(
              NativeJsonNormalizer.normalizeMap(raw),
            ),
          )
          .toList(growable: false),
    );
  }

  void _validate() {
    if (queryGeneration < 0 || queryGeneration > _maxSafeInteger) {
      throw const FormatException('Search query_generation is out of range.');
    }
    final keywordAnalysis = SearchTextContract.analyze(keyword);
    if (keywordAnalysis.normalizedDisplay.isEmpty ||
        keywordAnalysis.scalarCount >
            SearchTextContract.maximumKeywordScalars ||
        keywordAnalysis.utf8Bytes >
            SearchTextContract.maximumKeywordUtf8Bytes) {
      throw const FormatException(
        'Search keyword must contain 1..128 characters.',
      );
    }
    if (timezone.isEmpty || timezone.length > 255) {
      throw const FormatException(
        'Search timezone must contain 1..255 characters.',
      );
    }
    if (targetTypes.isEmpty ||
        targetTypes.length > 3 ||
        targetTypes.toSet().length != targetTypes.length ||
        !_isContractSubsequence(targetTypes)) {
      throw const FormatException(
        'Search target_types must be a fixed-order unique subset.',
      );
    }
    if ((dateFrom == null) != (dateToExclusive == null)) {
      throw const FormatException(
        'Search date range must be fully null or fully present.',
      );
    }
    if (dateFrom != null) {
      ContractValue.validateLocalDate(
        dateFrom!,
        field: 'SearchQuery.date_from',
      );
      ContractValue.validateLocalDate(
        dateToExclusive!,
        field: 'SearchQuery.date_to_exclusive',
      );
      if (dateFrom!.compareTo(dateToExclusive!) >= 0) {
        throw const FormatException('Search date range must be increasing.');
      }
    }
    final categories = categoryIds;
    if (categories == null) {
      if (includeUncategorized) {
        throw const FormatException(
          'Unfiltered categories cannot include uncategorized mode.',
        );
      }
    } else if (categories.length > 100 ||
        categories.toSet().length != categories.length ||
        categories.any((value) => value.isEmpty || value.length > 512) ||
        (categories.isEmpty && !includeUncategorized)) {
      throw const FormatException('Search category filter is invalid.');
    }
    if (sections.isEmpty ||
        sections.length > 3 ||
        sections.map((value) => value.targetType).toSet().length !=
            sections.length ||
        !_isContractSubsequence(
          sections.map((value) => value.targetType).toList(),
        ) ||
        sections.any((section) => !targetTypes.contains(section.targetType))) {
      throw const FormatException('Search sections are invalid.');
    }
    final continuationCount = sections
        .where((section) => section.cursor != null)
        .length;
    if (continuationCount > 1 ||
        (continuationCount == 1 && sections.length != 1)) {
      throw const FormatException(
        'Only one continuation section may be requested.',
      );
    }
  }

  Map<String, dynamic> toJson() => {
    'query_generation': queryGeneration,
    'keyword': keyword,
    'timezone': timezone,
    'target_types': targetTypes.map((value) => value.wireValue).toList(),
    'date_from': dateFrom,
    'date_to_exclusive': dateToExclusive,
    'category_ids': categoryIds,
    'include_uncategorized': includeUncategorized,
    'include_completed': includeCompleted,
    'sort_by': sortBy.wireValue,
    'sections': sections.map((value) => value.toJson()).toList(),
  };
}

class ReplaceSearchHistoryRequestDto {
  ReplaceSearchHistoryRequestDto({
    required this.expectedRevision,
    required List<String> items,
  }) : items = List.unmodifiable(items) {
    if (expectedRevision < 0 || expectedRevision > _maxSafeInteger) {
      throw const FormatException('History expected_revision is out of range.');
    }
    if (items.length > 20 || !_validHistoryItems(items)) {
      throw const FormatException('Search history items are invalid.');
    }
  }

  final int expectedRevision;
  final List<String> items;

  factory ReplaceSearchHistoryRequestDto.fromJson(Map<String, dynamic> json) {
    const parent = 'ReplaceSearchHistoryRequest';
    ContractValue.requireExactKeys(json, const {
      'expected_revision',
      'items',
    }, parent);
    return ReplaceSearchHistoryRequestDto(
      expectedRevision: ContractValue.integer(
        json,
        'expected_revision',
        parent,
        minimum: 0,
        maximum: _maxSafeInteger,
      ),
      items: ContractValue.stringList(json, 'items', parent, unique: true),
    );
  }

  Map<String, dynamic> toJson() => {
    'expected_revision': expectedRevision,
    'items': items,
  };
}

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

List<String>? _stringListOrNull(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) {
    throw const FormatException('Search category_ids must be array or null.');
  }
  return <String>[
    for (final value in raw)
      if (value is String)
        value
      else
        throw const FormatException('Search category ID must be a string.'),
  ];
}

bool _isContractSubsequence(List<SearchTargetType> values) {
  var previous = -1;
  for (final value in values) {
    final index = SearchTargetType.values.indexOf(value);
    if (index <= previous) return false;
    previous = index;
  }
  return true;
}

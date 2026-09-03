import '../../native_contract/search/search_contract_enums.dart';
import '../../native_contract/shared/civil_date.dart';

enum SearchDatePreset {
  any,
  today,
  pastSevenDays,
  nextSevenDays,
  thisMonth,
  custom,
}

class SearchDateFilter {
  const SearchDateFilter._({required this.preset, this.from, this.toExclusive});

  const SearchDateFilter.any() : this._(preset: SearchDatePreset.any);

  factory SearchDateFilter.preset(SearchDatePreset preset, CivilDate today) {
    return switch (preset) {
      SearchDatePreset.any => const SearchDateFilter.any(),
      SearchDatePreset.today => SearchDateFilter._(
        preset: preset,
        from: today,
        toExclusive: today.addDays(1),
      ),
      SearchDatePreset.pastSevenDays => SearchDateFilter._(
        preset: preset,
        from: today.addDays(-6),
        toExclusive: today.addDays(1),
      ),
      SearchDatePreset.nextSevenDays => SearchDateFilter._(
        preset: preset,
        from: today,
        toExclusive: today.addDays(7),
      ),
      SearchDatePreset.thisMonth => SearchDateFilter._(
        preset: preset,
        from: CivilDate(today.year, today.month, 1),
        toExclusive: CivilDate(today.year, today.month, 1).addMonthsClamped(1),
      ),
      SearchDatePreset.custom => throw ArgumentError(
        'Use SearchDateFilter.custom.',
      ),
    };
  }

  factory SearchDateFilter.custom({
    required CivilDate from,
    required CivilDate toInclusive,
  }) {
    if (from.compareTo(toInclusive) > 0) {
      throw const FormatException('Custom Search date range is reversed.');
    }
    return SearchDateFilter._(
      preset: SearchDatePreset.custom,
      from: from,
      toExclusive: toInclusive.addDays(1),
    );
  }

  final SearchDatePreset preset;
  final CivilDate? from;
  final CivilDate? toExclusive;

  SearchDateFilter rebase(CivilDate today) => preset == SearchDatePreset.custom
      ? this
      : SearchDateFilter.preset(preset, today);

  String? get dateFrom => from?.format();
  String? get dateToExclusive => toExclusive?.format();
  bool get isDefault => preset == SearchDatePreset.any;
}

class SearchFilters {
  SearchFilters({
    this.date = const SearchDateFilter.any(),
    Set<SearchTargetType>? targetTypes,
    List<String>? categoryIds,
    this.includeUncategorized = false,
    this.includeCompleted = true,
    this.sortBy = SearchSortBy.relevance,
  }) : targetTypes = Set.unmodifiable(
         targetTypes ?? SearchTargetType.values.toSet(),
       ),
       categoryIds = categoryIds == null
           ? null
           : List.unmodifiable(categoryIds) {
    if (this.targetTypes.isEmpty) {
      throw const FormatException(
        'At least one Search target type is required.',
      );
    }
    if (this.categoryIds == null && includeUncategorized) {
      throw const FormatException(
        'Uncategorized cannot be selected without a category filter.',
      );
    }
    if (this.categoryIds != null &&
        this.categoryIds!.isEmpty &&
        !includeUncategorized) {
      throw const FormatException(
        'Empty category filter must select uncategorized.',
      );
    }
  }

  final SearchDateFilter date;
  final Set<SearchTargetType> targetTypes;
  final List<String>? categoryIds;
  final bool includeUncategorized;
  final bool includeCompleted;
  final SearchSortBy sortBy;

  List<SearchTargetType> get orderedTargetTypes => SearchTargetType.values
      .where(targetTypes.contains)
      .toList(growable: false);

  int get activeGroupCount => <bool>[
    !date.isDefault,
    targetTypes.length != SearchTargetType.values.length,
    categoryIds != null,
    !includeCompleted,
    sortBy != SearchSortBy.relevance,
  ].where((value) => value).length;

  String get fingerprint => [
    date.preset.name,
    date.dateFrom ?? '-',
    date.dateToExclusive ?? '-',
    orderedTargetTypes.map((value) => value.wireValue).join(','),
    categoryIds?.join(',') ?? '-',
    includeUncategorized,
    includeCompleted,
    sortBy.wireValue,
  ].join('|');

  SearchFilters copyWith({
    SearchDateFilter? date,
    Set<SearchTargetType>? targetTypes,
    List<String>? categoryIds,
    bool clearCategoryIds = false,
    bool? includeUncategorized,
    bool? includeCompleted,
    SearchSortBy? sortBy,
  }) => SearchFilters(
    date: date ?? this.date,
    targetTypes: targetTypes ?? this.targetTypes,
    categoryIds: clearCategoryIds ? null : categoryIds ?? this.categoryIds,
    includeUncategorized: clearCategoryIds
        ? false
        : includeUncategorized ?? this.includeUncategorized,
    includeCompleted: includeCompleted ?? this.includeCompleted,
    sortBy: sortBy ?? this.sortBy,
  );
}

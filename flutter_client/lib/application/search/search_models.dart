import '../category/category_models.dart';
import '../../native_contract/search/search_contract_enums.dart';
import '../../native_contract/search/search_response_dtos.dart';
import '../../native_contract/shared/civil_date.dart';
import 'search_date_filter.dart';

enum SearchContentPhase {
  history,
  debouncing,
  initialLoading,
  ready,
  empty,
  error,
  refreshing,
}

enum SearchSectionPhase {
  ready,
  loadingMore,
  refreshing,
  loadMoreError,
  contractError,
}

enum SearchHistoryMode { browsing, managing }

enum SearchHistoryLoadPhase { loading, ready, error }

enum SearchHistoryWritePhase { idle, writing, error }

enum SearchCategoryLoadPhase { loading, ready, error }

class SearchSectionState {
  const SearchSectionState({
    required this.type,
    this.items = const [],
    this.totalCount = 0,
    this.hasMore = false,
    this.nextCursor,
    this.snapshotToken,
    this.evaluatedAt,
    this.phase = SearchSectionPhase.ready,
    this.errorMessage,
    this.operationEpoch = 0,
  });
  final SearchTargetType type;
  final List<SearchItemDto> items;
  final int totalCount;
  final bool hasMore;
  final String? nextCursor;
  final String? snapshotToken;
  final DateTime? evaluatedAt;
  final SearchSectionPhase phase;
  final String? errorMessage;
  final int operationEpoch;

  SearchSectionState copyWith({
    List<SearchItemDto>? items,
    int? totalCount,
    bool? hasMore,
    String? nextCursor,
    bool clearCursor = false,
    String? snapshotToken,
    bool clearSnapshot = false,
    DateTime? evaluatedAt,
    bool clearEvaluatedAt = false,
    SearchSectionPhase? phase,
    String? errorMessage,
    bool clearError = false,
    int? operationEpoch,
  }) => SearchSectionState(
    type: type,
    items: List.unmodifiable(items ?? this.items),
    totalCount: totalCount ?? this.totalCount,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    snapshotToken: clearSnapshot ? null : snapshotToken ?? this.snapshotToken,
    evaluatedAt: clearEvaluatedAt ? null : evaluatedAt ?? this.evaluatedAt,
    phase: phase ?? this.phase,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    operationEpoch: operationEpoch ?? this.operationEpoch,
  );
}

class SearchHistoryState {
  const SearchHistoryState({
    this.loadPhase = SearchHistoryLoadPhase.loading,
    this.writePhase = SearchHistoryWritePhase.idle,
    this.mode = SearchHistoryMode.browsing,
    this.items = const [],
    this.revision = 0,
    this.errorMessage,
    this.undoItems,
  });
  final SearchHistoryLoadPhase loadPhase;
  final SearchHistoryWritePhase writePhase;
  final SearchHistoryMode mode;
  final List<String> items;
  final int revision;
  final String? errorMessage;
  final List<String>? undoItems;

  SearchHistoryState copyWith({
    SearchHistoryLoadPhase? loadPhase,
    SearchHistoryWritePhase? writePhase,
    SearchHistoryMode? mode,
    List<String>? items,
    int? revision,
    String? errorMessage,
    bool clearError = false,
    List<String>? undoItems,
    bool clearUndo = false,
  }) => SearchHistoryState(
    loadPhase: loadPhase ?? this.loadPhase,
    writePhase: writePhase ?? this.writePhase,
    mode: mode ?? this.mode,
    items: List.unmodifiable(items ?? this.items),
    revision: revision ?? this.revision,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    undoItems: clearUndo ? null : undoItems ?? this.undoItems,
  );
}

class SearchState {
  SearchState({
    this.contentPhase = SearchContentPhase.history,
    this.rawKeyword = '',
    this.normalizedKeyword = '',
    this.isComposing = false,
    this.pendingKeyboardSubmit = false,
    SearchFilters? filters,
    this.displayedFingerprint,
    this.pendingFingerprint,
    Map<SearchTargetType, SearchSectionState>? sections,
    this.history = const SearchHistoryState(),
    this.timezone = '',
    CivilDate? today,
    this.queryGeneration = 0,
    this.snapshotToken,
    this.evaluatedAt,
    this.errorMessage,
    this.categories = const [],
    this.categoryLoadPhase = SearchCategoryLoadPhase.loading,
    this.categoryErrorMessage,
    this.scrollRestorationKey = 0,
  }) : filters = filters ?? SearchFilters(),
       today = today ?? CivilDate.fromDateTime(DateTime.now()),
       sections = Map.unmodifiable(
         sections ??
             {
               for (final type in SearchTargetType.values)
                 type: SearchSectionState(type: type),
             },
       );

  final SearchContentPhase contentPhase;
  final String rawKeyword;
  final String normalizedKeyword;
  final bool isComposing;
  final bool pendingKeyboardSubmit;
  final SearchFilters filters;
  final String? displayedFingerprint;
  final String? pendingFingerprint;
  final Map<SearchTargetType, SearchSectionState> sections;
  final SearchHistoryState history;
  final String timezone;
  final CivilDate today;
  final int queryGeneration;
  final String? snapshotToken;
  final DateTime? evaluatedAt;
  final String? errorMessage;
  final List<Category> categories;
  final SearchCategoryLoadPhase categoryLoadPhase;
  final String? categoryErrorMessage;
  final int scrollRestorationKey;

  bool get hasResults =>
      sections.values.any((section) => section.items.isNotEmpty);
  bool get resultsInteractive => contentPhase == SearchContentPhase.ready;
  SearchSectionState section(SearchTargetType type) => sections[type]!;

  SearchState copyWith({
    SearchContentPhase? contentPhase,
    String? rawKeyword,
    String? normalizedKeyword,
    bool? isComposing,
    bool? pendingKeyboardSubmit,
    SearchFilters? filters,
    String? displayedFingerprint,
    bool clearDisplayedFingerprint = false,
    String? pendingFingerprint,
    bool clearPendingFingerprint = false,
    Map<SearchTargetType, SearchSectionState>? sections,
    SearchHistoryState? history,
    String? timezone,
    CivilDate? today,
    int? queryGeneration,
    String? snapshotToken,
    bool clearSnapshot = false,
    DateTime? evaluatedAt,
    bool clearEvaluatedAt = false,
    String? errorMessage,
    bool clearError = false,
    List<Category>? categories,
    SearchCategoryLoadPhase? categoryLoadPhase,
    String? categoryErrorMessage,
    bool clearCategoryError = false,
    int? scrollRestorationKey,
  }) => SearchState(
    contentPhase: contentPhase ?? this.contentPhase,
    rawKeyword: rawKeyword ?? this.rawKeyword,
    normalizedKeyword: normalizedKeyword ?? this.normalizedKeyword,
    isComposing: isComposing ?? this.isComposing,
    pendingKeyboardSubmit: pendingKeyboardSubmit ?? this.pendingKeyboardSubmit,
    filters: filters ?? this.filters,
    displayedFingerprint: clearDisplayedFingerprint
        ? null
        : displayedFingerprint ?? this.displayedFingerprint,
    pendingFingerprint: clearPendingFingerprint
        ? null
        : pendingFingerprint ?? this.pendingFingerprint,
    sections: sections ?? this.sections,
    history: history ?? this.history,
    timezone: timezone ?? this.timezone,
    today: today ?? this.today,
    queryGeneration: queryGeneration ?? this.queryGeneration,
    snapshotToken: clearSnapshot ? null : snapshotToken ?? this.snapshotToken,
    evaluatedAt: clearEvaluatedAt ? null : evaluatedAt ?? this.evaluatedAt,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    categories: List.unmodifiable(categories ?? this.categories),
    categoryLoadPhase: categoryLoadPhase ?? this.categoryLoadPhase,
    categoryErrorMessage: clearCategoryError
        ? null
        : categoryErrorMessage ?? this.categoryErrorMessage,
    scrollRestorationKey: scrollRestorationKey ?? this.scrollRestorationKey,
  );
}

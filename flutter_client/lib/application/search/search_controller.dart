import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/category_repository.dart';
import '../../gateway_interfaces/search_gateway.dart';
import '../../gateway_interfaces/search_history_gateway.dart';
import '../../native_contract/search/search_contract_enums.dart';
import '../../native_contract/search/search_request_dtos.dart';
import '../../native_contract/search/search_response_dtos.dart';
import '../../native_contract/search/search_text_contract.dart';
import '../../native_contract/shared/civil_date.dart';
import 'search_civil_clock_coordinator.dart';
import 'search_date_filter.dart';
import 'search_failure_message.dart';
import 'search_history_coordinator.dart';
import 'search_models.dart';

enum SearchDetailMutation { unchanged, changed, deleted }

class SearchController extends ChangeNotifier {
  SearchController({
    required SearchGateway gateway,
    required SearchHistoryGateway historyGateway,
    required SearchTimezoneProvider timezoneProvider,
    required CategoryRepository categoryRepository,
    DateTime Function()? nowProvider,
    this.debounceDuration = const Duration(seconds: 1),
    Duration clockGuardInterval = const Duration(seconds: 60),
    Duration historyUndoWindow = const Duration(seconds: 6),
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider,
       _categoryRepository = categoryRepository,
       _nowProvider = nowProvider ?? DateTime.now {
    _history = SearchHistoryCoordinator(
      gateway: historyGateway,
      onChanged: _onHistoryChanged,
      undoWindow: historyUndoWindow,
    );
    _clock = SearchCivilClockCoordinator(
      timezoneProvider: timezoneProvider,
      nowProvider: _nowProvider,
      guardInterval: clockGuardInterval,
      onChanged: _onCivilClockChanged,
    );
    _state = SearchState(today: CivilDate.fromDateTime(_nowProvider()));
  }

  final SearchGateway _gateway;
  final SearchTimezoneProvider _timezoneProvider;
  final CategoryRepository _categoryRepository;
  final DateTime Function() _nowProvider;
  final Duration debounceDuration;
  late final SearchHistoryCoordinator _history;
  late final SearchCivilClockCoordinator _clock;
  late SearchState _state;
  SearchState get state => _state;

  Timer? _debounce;
  bool _initialized = false;
  bool _initializing = false;
  bool _active = false;
  bool _tabActive = false;
  bool _appLifecycleActive = true;
  bool _disposed = false;
  int _generation = 0;
  final Map<SearchTargetType, int> _sectionEpoch = {
    for (final type in SearchTargetType.values) type: 0,
  };

  Future<void> initialize() async {
    if (_initialized || _initializing || _disposed) return;
    _initializing = true;
    try {
      await Future.wait([_history.initialize(), _loadCategories()]);
      final timezone = await _timezoneProvider();
      if (_disposed) return;
      if (timezone.isEmpty) {
        throw StateError('Device IANA timezone is unavailable.');
      }
      _initialized = true;
      _setState(
        _state.copyWith(
          timezone: timezone,
          today: CivilDate.fromDateTime(_nowProvider()),
          contentPhase: SearchContentPhase.history,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_disposed) {
        _setState(
          _state.copyWith(
            contentPhase: SearchContentPhase.error,
            errorMessage: searchFailureMessage(error),
          ),
        );
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> retryInitialize() async {
    _initialized = false;
    await initialize();
    if (_active) await _clock.resume();
  }

  Future<void> setActive(bool active) async {
    _tabActive = active;
    await _syncActivity();
  }

  Future<void> setAppLifecycleActive(bool active) async {
    _appLifecycleActive = active;
    await _syncActivity();
  }

  Future<void> _syncActivity() async {
    final active = _tabActive && _appLifecycleActive;
    if (_disposed || _active == active) return;
    _active = active;
    if (!active) {
      _debounce?.cancel();
      _invalidateGeneration();
      _clock.pause();
      _history.dismissUndo();
      _settleInterruptedOperations();
      return;
    }
    await initialize();
    if (!_initialized || _disposed) return;
    await _clock.resume();
    if (_wireKeyword.isNotEmpty &&
        _state.displayedFingerprint != _fingerprint(_wireKeyword)) {
      await _runInitialQuery();
    }
  }

  void updateText(String value, {required bool isComposing}) {
    if (_disposed) return;
    _debounce?.cancel();
    final wasComposing = _state.isComposing;
    _invalidateGeneration();
    final isBlank = SearchTextContract.isBlank(value);
    _setState(
      _state.copyWith(
        rawKeyword: value,
        isComposing: isComposing,
        contentPhase: isBlank
            ? SearchContentPhase.history
            : isComposing
            ? _state.contentPhase
            : SearchContentPhase.debouncing,
        sections: isBlank ? _emptySections() : null,
        normalizedKeyword: isBlank ? '' : null,
        clearDisplayedFingerprint: isBlank,
        clearPendingFingerprint: true,
        clearSnapshot: isBlank,
        clearEvaluatedAt: isBlank,
        clearError: true,
      ),
    );
    if (isBlank || isComposing || !_active || !_initialized) {
      return;
    }
    if (wasComposing && _state.pendingKeyboardSubmit) {
      _setState(_state.copyWith(pendingKeyboardSubmit: false));
      unawaited(_runInitialQuery(recordHistory: true));
      return;
    }
    _debounce = Timer(debounceDuration, () => unawaited(_runInitialQuery()));
  }

  Future<void> submit() async {
    if (_wireKeyword.isEmpty) return;
    _debounce?.cancel();
    if (_state.isComposing) {
      _setState(_state.copyWith(pendingKeyboardSubmit: true));
      return;
    }
    await _runInitialQuery(recordHistory: true);
  }

  void clearKeyword() {
    _debounce?.cancel();
    _invalidateGeneration();
    _setState(
      _state.copyWith(
        contentPhase: SearchContentPhase.history,
        rawKeyword: '',
        normalizedKeyword: '',
        isComposing: false,
        pendingKeyboardSubmit: false,
        sections: _emptySections(),
        clearDisplayedFingerprint: true,
        clearPendingFingerprint: true,
        clearSnapshot: true,
        clearEvaluatedAt: true,
        clearError: true,
        scrollRestorationKey: _state.scrollRestorationKey + 1,
      ),
    );
  }

  Future<void> applyFilters(SearchFilters filters) async {
    _debounce?.cancel();
    _invalidateGeneration();
    _setState(
      _state.copyWith(
        filters: filters,
        sections: {
          for (final type in SearchTargetType.values)
            type: filters.targetTypes.contains(type)
                ? _state
                      .section(type)
                      .copyWith(
                        phase: _state.section(type).items.isEmpty
                            ? SearchSectionPhase.ready
                            : SearchSectionPhase.refreshing,
                        clearCursor: true,
                        clearError: true,
                      )
                : SearchSectionState(type: type),
        },
        clearPendingFingerprint: true,
        clearError: true,
      ),
    );
    if (_wireKeyword.isNotEmpty && _active) await _runInitialQuery();
  }

  Future<void> resetFilters() => applyFilters(SearchFilters());

  Future<void> removeDateFilter() =>
      applyFilters(_state.filters.copyWith(date: const SearchDateFilter.any()));

  Future<void> removeCategoryFilter() =>
      applyFilters(_state.filters.copyWith(clearCategoryIds: true));

  Future<void> removeTypeFilter() => applyFilters(
    _state.filters.copyWith(targetTypes: SearchTargetType.values.toSet()),
  );

  Future<void> removeCompletionFilter() =>
      applyFilters(_state.filters.copyWith(includeCompleted: true));

  Future<void> removeSortFilter() =>
      applyFilters(_state.filters.copyWith(sortBy: SearchSortBy.relevance));

  Future<void> retry() => _runInitialQuery();

  Future<void> loadMore(SearchTargetType type) async {
    if (_disposed || !_active || !_initialized || !_state.resultsInteractive) {
      return;
    }
    final current = _state.section(type);
    if (!current.hasMore ||
        current.nextCursor == null ||
        current.phase == SearchSectionPhase.loadingMore ||
        !_state.filters.targetTypes.contains(type)) {
      return;
    }
    final generation = _generation;
    final epoch = (_sectionEpoch[type] ?? 0) + 1;
    _sectionEpoch[type] = epoch;
    _replaceSection(
      type,
      current.copyWith(
        phase: SearchSectionPhase.loadingMore,
        operationEpoch: epoch,
        clearError: true,
      ),
    );
    final request = _request(
      generation: generation,
      sections: [
        SearchSectionRequestDto(targetType: type, cursor: current.nextCursor),
      ],
    );
    try {
      final response = await _gateway.query(request);
      if (!_isSectionCurrent(type, generation, epoch)) return;
      final page = response.sections.single;
      _validateContinuation(current, response, page);
      final combined = [...current.items, ...page.items];
      _validateConservation(page, combined.length);
      _replaceSection(
        type,
        current.copyWith(
          items: combined,
          totalCount: page.totalCount,
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          phase: SearchSectionPhase.ready,
          operationEpoch: epoch,
          clearError: true,
        ),
      );
    } catch (error) {
      if (!_isSectionCurrent(type, generation, epoch)) return;
      if (error is SearchGatewayFailure && error.isCursorExpired) {
        await _refreshSections({type});
        return;
      }
      final contract =
          error is FormatException ||
          (error is SearchGatewayFailure &&
              {
                'SEARCH_CURSOR_INVALID',
                'SEARCH_CURSOR_QUERY_MISMATCH',
                'CONTRACT_VALIDATION_FAILED',
              }.contains(error.code));
      _replaceSection(
        type,
        current.copyWith(
          phase: contract
              ? SearchSectionPhase.contractError
              : SearchSectionPhase.loadMoreError,
          errorMessage: searchFailureMessage(error),
          operationEpoch: epoch,
        ),
      );
    }
  }

  Future<void> refreshAfterDetail(
    SearchTargetType type,
    SearchDetailMutation mutation,
  ) async {
    if (mutation == SearchDetailMutation.unchanged || _wireKeyword.isEmpty) {
      return;
    }
    await _refreshSections({
      type,
    }, replayCount: _state.section(type).items.length);
  }

  void recordOpenedResult() {
    final keyword = _state.normalizedKeyword;
    if (keyword.isNotEmpty) _history.record(keyword);
  }

  Future<void> selectHistory(String keyword) async {
    _history.record(keyword);
    _setState(_state.copyWith(rawKeyword: keyword, isComposing: false));
    await _runInitialQuery();
  }

  void enterHistoryManaging() => _history.enterManaging();
  void exitHistoryManaging() => _history.exitManaging();
  void removeHistory(String keyword) => _history.remove(keyword);
  void clearHistory() => _history.clear();
  void undoClearHistory() => _history.undoClear();
  Future<void> retryHistory() => _history.initialize();

  Future<void> retryCategories() => _loadCategories();

  Future<void> _loadCategories() async {
    _setState(
      _state.copyWith(
        categoryLoadPhase: SearchCategoryLoadPhase.loading,
        clearCategoryError: true,
      ),
    );
    try {
      final categories = await _categoryRepository.listActiveCategories();
      if (_disposed) return;
      _setState(
        _state.copyWith(
          categories: categories,
          categoryLoadPhase: SearchCategoryLoadPhase.ready,
          clearCategoryError: true,
        ),
      );
    } catch (_) {
      if (_disposed) return;
      _setState(
        _state.copyWith(
          categoryLoadPhase: SearchCategoryLoadPhase.error,
          categoryErrorMessage: '分类暂时无法加载，其他筛选仍可使用',
        ),
      );
    }
  }

  Future<void> _runInitialQuery({bool recordHistory = false}) =>
      _refreshSections(
        _state.filters.targetTypes,
        recordHistory: recordHistory,
      );

  Future<void> _refreshSections(
    Set<SearchTargetType> requested, {
    bool recordHistory = false,
    int? replayCount,
  }) async {
    if (_disposed || !_active || !_initialized || _wireKeyword.isEmpty) return;
    final types = SearchTargetType.values
        .where(
          (type) =>
              requested.contains(type) &&
              _state.filters.targetTypes.contains(type),
        )
        .toList(growable: false);
    if (types.isEmpty) return;
    _debounce?.cancel();
    final generation = _nextGeneration();
    final fingerprint = _fingerprint(_wireKeyword);
    final hadResults = _state.hasResults;
    final nextSections = Map<SearchTargetType, SearchSectionState>.from(
      _state.sections,
    );
    for (final type in SearchTargetType.values.where(
      (type) => !types.contains(type),
    )) {
      final existing = nextSections[type]!;
      if (existing.phase == SearchSectionPhase.loadingMore ||
          existing.phase == SearchSectionPhase.refreshing) {
        nextSections[type] = existing.copyWith(
          phase: SearchSectionPhase.ready,
          clearError: true,
        );
      }
    }
    for (final type in types) {
      final epoch = (_sectionEpoch[type] ?? 0) + 1;
      _sectionEpoch[type] = epoch;
      final existing = nextSections[type]!;
      nextSections[type] = existing.copyWith(
        phase: existing.items.isEmpty
            ? SearchSectionPhase.ready
            : SearchSectionPhase.refreshing,
        operationEpoch: epoch,
        clearCursor: true,
        clearError: true,
      );
    }
    _setState(
      _state.copyWith(
        contentPhase: hadResults
            ? SearchContentPhase.refreshing
            : SearchContentPhase.initialLoading,
        queryGeneration: generation,
        pendingFingerprint: fingerprint,
        sections: nextSections,
        clearError: true,
      ),
    );
    final request = _request(
      generation: generation,
      sections: [
        for (final type in types)
          SearchSectionRequestDto(targetType: type, cursor: null),
      ],
    );
    try {
      final response = await _gateway.query(request);
      if (!_isCurrent(generation, fingerprint)) return;
      _validateInitial(request, response);
      final accepted = Map<SearchTargetType, SearchSectionState>.from(
        _state.sections,
      );
      for (final page in response.sections) {
        _validateConservation(page, page.items.length);
        accepted[page.targetType] = SearchSectionState(
          type: page.targetType,
          items: page.items,
          totalCount: page.totalCount,
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
          snapshotToken: response.snapshotToken,
          evaluatedAt: response.evaluatedAt,
          phase: SearchSectionPhase.ready,
          operationEpoch: _sectionEpoch[page.targetType]!,
        );
      }
      _setState(
        _state.copyWith(
          contentPhase:
              accepted.values.any((section) => section.items.isNotEmpty)
              ? SearchContentPhase.ready
              : SearchContentPhase.empty,
          normalizedKeyword: response.normalizedKeyword,
          displayedFingerprint: fingerprint,
          clearPendingFingerprint: true,
          sections: accepted,
          snapshotToken: response.snapshotToken,
          evaluatedAt: response.evaluatedAt,
          clearError: true,
        ),
      );
      if (recordHistory) _history.record(response.normalizedKeyword);
      if (replayCount != null && replayCount > searchPageSize) {
        final type = types.single;
        while (!_disposed &&
            _isCurrent(generation, fingerprint) &&
            _state.section(type).hasMore &&
            _state.section(type).items.length < replayCount) {
          await loadMore(type);
        }
      }
    } catch (error) {
      if (!_isCurrent(generation, fingerprint)) return;
      final restored = {
        for (final entry in _state.sections.entries)
          entry.key: entry.value.copyWith(
            phase: entry.value.items.isEmpty
                ? SearchSectionPhase.ready
                : SearchSectionPhase.ready,
          ),
      };
      _setState(
        _state.copyWith(
          contentPhase: hadResults
              ? SearchContentPhase.ready
              : SearchContentPhase.error,
          sections: restored,
          errorMessage: searchFailureMessage(error),
          clearPendingFingerprint: true,
        ),
      );
    }
  }

  SearchQueryRequestDto _request({
    required int generation,
    required List<SearchSectionRequestDto> sections,
  }) => SearchQueryRequestDto(
    queryGeneration: generation,
    keyword: _wireKeyword,
    timezone: _state.timezone,
    targetTypes: _state.filters.orderedTargetTypes,
    dateFrom: _state.filters.date.dateFrom,
    dateToExclusive: _state.filters.date.dateToExclusive,
    categoryIds: _state.filters.categoryIds,
    includeUncategorized: _state.filters.includeUncategorized,
    includeCompleted: _state.filters.includeCompleted,
    sortBy: _state.filters.sortBy,
    sections: sections,
  );

  void _validateInitial(
    SearchQueryRequestDto request,
    SearchQueryResponseDto response,
  ) {
    final expected = request.sections
        .map((section) => section.targetType)
        .toList();
    final actual = response.sections
        .map((section) => section.targetType)
        .toList();
    if (response.queryGeneration != request.queryGeneration ||
        response.timezone != request.timezone ||
        !_sameTypes(expected, actual)) {
      throw const FormatException(
        'Search initial response does not match request.',
      );
    }
  }

  void _validateContinuation(
    SearchSectionState current,
    SearchQueryResponseDto response,
    SearchSectionResponseDto page,
  ) {
    if (response.queryGeneration != _generation ||
        response.timezone != _state.timezone ||
        page.targetType != current.type ||
        response.snapshotToken != current.snapshotToken ||
        response.evaluatedAt != current.evaluatedAt ||
        page.totalCount != current.totalCount ||
        page.nextCursor == current.nextCursor ||
        page.items.any(
          (item) =>
              current.items.any((old) => old.identityKey == item.identityKey),
        )) {
      throw const FormatException(
        'Search continuation response drifted from its cursor chain.',
      );
    }
  }

  void _validateConservation(SearchSectionResponseDto page, int accumulated) {
    if (page.hasMore != (accumulated < page.totalCount) ||
        (!page.hasMore && accumulated != page.totalCount) ||
        (page.hasMore && page.items.length != searchPageSize)) {
      throw const FormatException('Search pagination conservation failed.');
    }
  }

  Future<void> _onCivilClockChanged(String timezone, CivilDate today) async {
    if (_disposed) return;
    if (_state.timezone == timezone && _state.today.compareTo(today) == 0) {
      return;
    }
    _debounce?.cancel();
    _invalidateGeneration();
    final filters = _state.filters.copyWith(
      date: _state.filters.date.rebase(today),
    );
    _setState(
      _state.copyWith(
        timezone: timezone,
        today: today,
        filters: filters,
        sections: {
          for (final type in SearchTargetType.values)
            type: _state
                .section(type)
                .copyWith(
                  clearCursor: true,
                  clearSnapshot: true,
                  clearEvaluatedAt: true,
                  hasMore: false,
                  phase: SearchSectionPhase.ready,
                ),
        },
        clearSnapshot: true,
        clearEvaluatedAt: true,
      ),
    );
    if (_wireKeyword.isNotEmpty && _active) await _runInitialQuery();
  }

  void _onHistoryChanged(SearchHistoryState history) {
    if (!_disposed) _setState(_state.copyWith(history: history));
  }

  void _replaceSection(SearchTargetType type, SearchSectionState value) {
    final sections = Map<SearchTargetType, SearchSectionState>.from(
      _state.sections,
    );
    sections[type] = value;
    _setState(_state.copyWith(sections: sections));
  }

  Map<SearchTargetType, SearchSectionState> _emptySections() => {
    for (final type in SearchTargetType.values)
      type: SearchSectionState(type: type),
  };

  String get _wireKeyword =>
      SearchTextContract.normalizeForWire(_state.rawKeyword);
  String _fingerprint(String keyword) =>
      '$keyword|${_state.filters.fingerprint}|${_state.timezone}';

  int _nextGeneration() {
    _generation += 1;
    return _generation;
  }

  void _invalidateGeneration() {
    _generation += 1;
    for (final type in SearchTargetType.values) {
      _sectionEpoch[type] = (_sectionEpoch[type] ?? 0) + 1;
    }
  }

  void _settleInterruptedOperations() {
    final sections = {
      for (final entry in _state.sections.entries)
        entry.key:
            entry.value.phase == SearchSectionPhase.loadingMore ||
                entry.value.phase == SearchSectionPhase.refreshing
            ? entry.value.copyWith(
                phase: SearchSectionPhase.ready,
                clearError: true,
              )
            : entry.value,
    };
    _setState(
      _state.copyWith(
        contentPhase: _state.contentPhase == SearchContentPhase.refreshing
            ? (_state.hasResults
                  ? SearchContentPhase.ready
                  : SearchContentPhase.empty)
            : _state.contentPhase,
        sections: sections,
      ),
    );
  }

  bool _isCurrent(int generation, String fingerprint) =>
      !_disposed &&
      _active &&
      generation == _generation &&
      fingerprint == _fingerprint(_wireKeyword);

  bool _isSectionCurrent(SearchTargetType type, int generation, int epoch) =>
      !_disposed &&
      _active &&
      generation == _generation &&
      _sectionEpoch[type] == epoch;

  void _setState(SearchState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _debounce?.cancel();
    _invalidateGeneration();
    _clock.dispose();
    _history.dispose();
    super.dispose();
  }
}

bool _sameTypes(List<SearchTargetType> first, List<SearchTargetType> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

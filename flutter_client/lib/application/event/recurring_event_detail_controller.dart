import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../../native_contract/event/event_occurrence_state_response_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../reminder/reconcile_reminder_schedule_use_case.dart';
import '../timezone/timezone_application_service.dart';
import 'recurring_event_actions.dart';
import 'recurring_event_detail_loader.dart';
import 'recurring_event_detail_models.dart';

export 'recurring_event_detail_models.dart';

const Object _notProvided = Object();

enum RecurringEventDetailPhase { idle, loading, ready, failure }

@immutable
class RecurringEventDetailState {
  const RecurringEventDetailState({
    required this.phase,
    required this.occurrences,
    required this.hasMore,
    required this.isRefreshing,
    required this.isLoadingMore,
    required this.occurrenceMutations,
    required this.isDeleted,
    this.detail,
    this.localizedEventTimeRange,
    this.referenceLocalNow,
    this.nextCursor,
    this.focusOccurrenceKey,
    this.seriesMutation,
    this.loadFailure,
    this.paginationFailure,
    this.actionFailure,
    this.reconcileWarning,
  });

  factory RecurringEventDetailState.initial({String? focusOccurrenceKey}) {
    return RecurringEventDetailState(
      phase: RecurringEventDetailPhase.idle,
      occurrences: const [],
      hasMore: false,
      isRefreshing: false,
      isLoadingMore: false,
      occurrenceMutations: const {},
      isDeleted: false,
      focusOccurrenceKey: focusOccurrenceKey,
    );
  }

  final RecurringEventDetailPhase phase;
  final EventDetailResponseDto? detail;
  final LocalizedTimeRange? localizedEventTimeRange;
  final LocalWallDateTime? referenceLocalNow;
  final List<RecurringEventOccurrenceItem> occurrences;
  final bool hasMore;
  final String? nextCursor;
  final String? focusOccurrenceKey;
  final bool isRefreshing;
  final bool isLoadingMore;
  final Map<String, RecurringEventOccurrenceMutation> occurrenceMutations;
  final RecurringEventSeriesMutation? seriesMutation;
  final bool isDeleted;
  final RecurringEventFailure? loadFailure;
  final RecurringEventFailure? paginationFailure;
  final RecurringEventFailure? actionFailure;
  final RecurringEventFailure? reconcileWarning;

  EventResponseDto? get event => detail?.event;
  bool get isReady => phase == RecurringEventDetailPhase.ready;
  bool get isRecurring => detail?.recurrence != null;
  bool get hasMutationInProgress =>
      seriesMutation != null || occurrenceMutations.isNotEmpty;

  bool isOccurrenceMutating(String occurrenceKey) {
    return occurrenceMutations.containsKey(occurrenceKey);
  }

  RecurringEventDetailState copyWith({
    RecurringEventDetailPhase? phase,
    Object? detail = _notProvided,
    Object? localizedEventTimeRange = _notProvided,
    Object? referenceLocalNow = _notProvided,
    List<RecurringEventOccurrenceItem>? occurrences,
    bool? hasMore,
    Object? nextCursor = _notProvided,
    bool? isRefreshing,
    bool? isLoadingMore,
    Map<String, RecurringEventOccurrenceMutation>? occurrenceMutations,
    Object? seriesMutation = _notProvided,
    bool? isDeleted,
    Object? loadFailure = _notProvided,
    Object? paginationFailure = _notProvided,
    Object? actionFailure = _notProvided,
    Object? reconcileWarning = _notProvided,
  }) {
    return RecurringEventDetailState(
      phase: phase ?? this.phase,
      detail: identical(detail, _notProvided)
          ? this.detail
          : detail as EventDetailResponseDto?,
      localizedEventTimeRange: identical(localizedEventTimeRange, _notProvided)
          ? this.localizedEventTimeRange
          : localizedEventTimeRange as LocalizedTimeRange?,
      referenceLocalNow: identical(referenceLocalNow, _notProvided)
          ? this.referenceLocalNow
          : referenceLocalNow as LocalWallDateTime?,
      occurrences: occurrences ?? this.occurrences,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: identical(nextCursor, _notProvided)
          ? this.nextCursor
          : nextCursor as String?,
      focusOccurrenceKey: focusOccurrenceKey,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      occurrenceMutations: occurrenceMutations ?? this.occurrenceMutations,
      seriesMutation: identical(seriesMutation, _notProvided)
          ? this.seriesMutation
          : seriesMutation as RecurringEventSeriesMutation?,
      isDeleted: isDeleted ?? this.isDeleted,
      loadFailure: identical(loadFailure, _notProvided)
          ? this.loadFailure
          : loadFailure as RecurringEventFailure?,
      paginationFailure: identical(paginationFailure, _notProvided)
          ? this.paginationFailure
          : paginationFailure as RecurringEventFailure?,
      actionFailure: identical(actionFailure, _notProvided)
          ? this.actionFailure
          : actionFailure as RecurringEventFailure?,
      reconcileWarning: identical(reconcileWarning, _notProvided)
          ? this.reconcileWarning
          : reconcileWarning as RecurringEventFailure?,
    );
  }
}

class RecurringEventDetailController extends ChangeNotifier {
  RecurringEventDetailController({
    required String eventId,
    required EventNativeGateway gateway,
    required TimezoneApplicationService timezoneService,
    required ReconcileReminderScheduleUseCase reconcileReminderScheduleUseCase,
    DateTime Function()? clock,
    Duration pastExtent = const Duration(days: 7),
    Duration futureExtent = const Duration(days: 90),
    int pageSize = 100,
    String? focusOccurrenceKey,
  }) : _eventId = eventId,
       _detailLoader = RecurringEventDetailLoader(
         eventId: eventId,
         gateway: gateway,
         timezoneService: timezoneService,
         clock: clock,
         pastExtent: pastExtent,
         futureExtent: futureExtent,
         pageSize: pageSize,
       ),
       _occurrenceActionUseCase = RecurringEventOccurrenceActionUseCase(
         gateway: gateway,
         reconcileUseCase: reconcileReminderScheduleUseCase,
       ),
       _seriesActionUseCase = RecurringEventSeriesActionUseCase(
         gateway: gateway,
         reconcileUseCase: reconcileReminderScheduleUseCase,
       ),
       _state = RecurringEventDetailState.initial(
         focusOccurrenceKey: focusOccurrenceKey,
       );

  final String _eventId;
  final RecurringEventDetailLoader _detailLoader;
  final RecurringEventOccurrenceActionUseCase _occurrenceActionUseCase;
  final RecurringEventSeriesActionUseCase _seriesActionUseCase;

  RecurringEventDetailState _state;
  RecurringOccurrenceQuery? _activeQuery;
  int _loadGeneration = 0;
  bool _isDisposed = false;

  RecurringEventDetailState get state => _state;

  Future<void> load() async {
    await _load(preserveContent: _state.detail != null);
  }

  Future<void> refresh() async {
    await _load(preserveContent: _state.detail != null);
  }

  Future<void> loadMore() async {
    final query = _activeQuery;
    final detail = _state.detail;
    if (_isDisposed ||
        detail == null ||
        detail.recurrence == null ||
        query == null ||
        !_state.hasMore ||
        _state.isLoadingMore) {
      return;
    }
    final cursor = _state.nextCursor;
    if (cursor == null) {
      _emit(
        _state.copyWith(
          paginationFailure: const RecurringEventFailure(
            message: 'Native 返回了无法继续分页的游标状态',
          ),
        ),
      );
      return;
    }

    final generation = _loadGeneration;
    _emit(_state.copyWith(isLoadingMore: true, paginationFailure: null));
    try {
      final page = await _detailLoader.loadMore(
        query: query,
        detail: detail,
        cursor: cursor,
      );
      if (!_isCurrentLoad(generation)) return;
      final merged = <String, RecurringEventOccurrenceItem>{
        for (final item in _state.occurrences) item.occurrenceKey: item,
        for (final item in page.occurrences) item.occurrenceKey: item,
      };
      _emit(
        _state.copyWith(
          occurrences: List.unmodifiable(merged.values),
          hasMore: page.hasMore,
          nextCursor: page.nextCursor,
          isLoadingMore: false,
          paginationFailure: null,
        ),
      );
    } on RecurringEventDetailLoadException catch (error) {
      if (_isCurrentLoad(generation)) {
        _finishPaginationFailure(error.failure);
      }
    }
  }

  Future<RecurringEventActionResult> completeOccurrence(String occurrenceKey) {
    return _mutateOccurrence(
      occurrenceKey,
      RecurringEventOccurrenceMutation.complete,
    );
  }

  Future<RecurringEventActionResult> reopenOccurrence(String occurrenceKey) {
    return _mutateOccurrence(
      occurrenceKey,
      RecurringEventOccurrenceMutation.reopen,
    );
  }

  Future<RecurringEventActionResult> skipOccurrence(String occurrenceKey) {
    return _mutateOccurrence(
      occurrenceKey,
      RecurringEventOccurrenceMutation.skip,
    );
  }

  Future<RecurringEventActionResult> cancelOccurrence(String occurrenceKey) {
    return _mutateOccurrence(
      occurrenceKey,
      RecurringEventOccurrenceMutation.cancel,
    );
  }

  Future<RecurringEventActionResult> completeSeries() {
    return _mutateSeries(RecurringEventSeriesMutation.complete);
  }

  Future<RecurringEventActionResult> reopenSeries() {
    return _mutateSeries(RecurringEventSeriesMutation.reopen);
  }

  Future<RecurringEventActionResult> cancelSeries() {
    return _mutateSeries(RecurringEventSeriesMutation.cancel);
  }

  Future<RecurringEventActionResult> deleteSeries({String? reason}) {
    return _mutateSeries(
      RecurringEventSeriesMutation.delete,
      deleteReason: reason,
    );
  }

  Future<RecurringEventFailure?> _load({required bool preserveContent}) async {
    final generation = ++_loadGeneration;
    if (preserveContent) {
      _emit(
        _state.copyWith(
          isRefreshing: true,
          isLoadingMore: false,
          loadFailure: null,
          paginationFailure: null,
        ),
      );
    } else {
      _activeQuery = null;
      _emit(
        RecurringEventDetailState.initial(
          focusOccurrenceKey: _state.focusOccurrenceKey,
        ).copyWith(phase: RecurringEventDetailPhase.loading),
      );
    }

    try {
      final data = await _detailLoader.load();
      if (!_isCurrentLoad(generation)) return null;
      _activeQuery = data.query;
      _commitLoaded(
        detail: data.detail,
        localizedEventTimeRange: data.localizedEventTimeRange,
        referenceLocalNow: data.referenceLocalNow,
        occurrences: data.occurrences,
        hasMore: data.hasMore,
        nextCursor: data.nextCursor,
      );
      return null;
    } on RecurringEventDetailLoadException catch (error) {
      if (!_isCurrentLoad(generation)) return null;
      return _finishLoadFailure(generation, preserveContent, error.failure);
    }
  }

  Future<RecurringEventActionResult> _mutateOccurrence(
    String occurrenceKey,
    RecurringEventOccurrenceMutation mutation,
  ) async {
    final readinessFailure = _seriesReadinessFailure();
    if (readinessFailure != null) {
      return RecurringEventActionResult.failure(readinessFailure);
    }
    if (_state.seriesMutation != null) {
      return RecurringEventActionResult.ignored('整个系列正在处理中');
    }
    if (_state.isOccurrenceMutating(occurrenceKey)) {
      return RecurringEventActionResult.ignored('该 occurrence 正在处理中');
    }
    final item = _findOccurrence(occurrenceKey);
    if (item == null) {
      return const RecurringEventActionResult.failure(
        RecurringEventFailure(message: '当前查询窗口中没有这个 occurrence'),
      );
    }
    final detail = _state.detail!;
    if (item.occurrence.recurrenceRevision != detail.recurrence!.revision) {
      return const RecurringEventActionResult.failure(
        RecurringEventFailure(message: '重复规则已经变化，请刷新后重试'),
      );
    }

    final mutations = Map<String, RecurringEventOccurrenceMutation>.of(
      _state.occurrenceMutations,
    )..[occurrenceKey] = mutation;
    _emit(
      _state.copyWith(
        occurrenceMutations: Map.unmodifiable(mutations),
        actionFailure: null,
      ),
    );
    final execution = await _occurrenceActionUseCase.execute(
      eventId: _eventId,
      detail: detail,
      occurrence: item.occurrence,
      mutation: mutation,
    );
    if (!execution.succeeded) {
      return _finishOccurrenceFailure(occurrenceKey, execution.failure!);
    }
    final updatedItems = _state.occurrences
        .map(
          (current) => current.occurrenceKey == occurrenceKey
              ? RecurringEventOccurrenceItem(
                  occurrence: _occurrenceWithState(
                    current.occurrence,
                    execution.state!,
                  ),
                  localizedTimeRange: current.localizedTimeRange,
                )
              : current,
        )
        .toList(growable: false);
    _emit(
      _state.copyWith(
        occurrences: List.unmodifiable(updatedItems),
        actionFailure: null,
      ),
    );
    _finishOccurrenceSuccess(occurrenceKey, warning: execution.warning);
    return RecurringEventActionResult.success(warning: execution.warning);
  }

  Future<RecurringEventActionResult> _mutateSeries(
    RecurringEventSeriesMutation mutation, {
    String? deleteReason,
  }) async {
    final readinessFailure = _seriesReadinessFailure();
    if (readinessFailure != null) {
      return RecurringEventActionResult.failure(readinessFailure);
    }
    if (_state.hasMutationInProgress) {
      return RecurringEventActionResult.ignored('另一个重复日程操作正在进行');
    }

    final detail = _state.detail!;
    _emit(_state.copyWith(seriesMutation: mutation, actionFailure: null));
    final execution = await _seriesActionUseCase.execute(
      eventId: _eventId,
      detail: detail,
      mutation: mutation,
      deleteReason: deleteReason,
    );
    if (!execution.succeeded) {
      return _finishSeriesFailure(execution.failure!);
    }
    final event = execution.event!;
    if (execution.deleted) {
      _loadGeneration += 1;
      _activeQuery = null;
      _emit(
        _state.copyWith(
          detail: _detailWithEvent(detail, event),
          occurrences: const [],
          hasMore: false,
          nextCursor: null,
          isDeleted: true,
          actionFailure: null,
        ),
      );
      _finishSeriesSuccess(warning: execution.warning);
      return RecurringEventActionResult.success(warning: execution.warning);
    }
    _emit(
      _state.copyWith(
        detail: _detailWithEvent(_state.detail ?? detail, event),
        actionFailure: null,
      ),
    );
    final refreshFailure = await _load(preserveContent: true);
    _finishSeriesSuccess(warning: execution.warning);
    return RecurringEventActionResult.success(
      warning: execution.warning ?? refreshFailure,
    );
  }

  RecurringEventFailure? _seriesReadinessFailure() {
    if (!_state.isReady || _state.detail == null) {
      return const RecurringEventFailure(message: '日程详情尚未加载完成');
    }
    if (_state.isDeleted) {
      return const RecurringEventFailure(message: '该重复日程已经删除');
    }
    if (_state.detail!.recurrence == null) {
      return const RecurringEventFailure(message: '该日程不是重复日程');
    }
    return null;
  }

  EventOccurrenceResponseDto _occurrenceWithState(
    EventOccurrenceResponseDto occurrence,
    EventOccurrenceStateResponseDto state,
  ) {
    return EventOccurrenceResponseDto(
      eventId: occurrence.eventId,
      recurrenceRevision: occurrence.recurrenceRevision,
      occurrenceKey: occurrence.occurrenceKey,
      occurrenceStartAt: occurrence.occurrenceStartAt,
      occurrenceEndAt: occurrence.occurrenceEndAt,
      occurrenceStartDate: occurrence.occurrenceStartDate,
      occurrenceEndDate: occurrence.occurrenceEndDate,
      timezone: occurrence.timezone,
      state: state,
    );
  }

  EventDetailResponseDto _detailWithEvent(
    EventDetailResponseDto detail,
    EventResponseDto event,
  ) {
    return EventDetailResponseDto(
      event: event,
      recurrence: detail.recurrence,
      reminders: detail.reminders,
      category: detail.category,
    );
  }

  RecurringEventOccurrenceItem? _findOccurrence(String occurrenceKey) {
    for (final item in _state.occurrences) {
      if (item.occurrenceKey == occurrenceKey) return item;
    }
    return null;
  }

  void _commitLoaded({
    required EventDetailResponseDto detail,
    required LocalizedTimeRange localizedEventTimeRange,
    required LocalWallDateTime referenceLocalNow,
    required List<RecurringEventOccurrenceItem> occurrences,
    required bool hasMore,
    required String? nextCursor,
  }) {
    _emit(
      _state.copyWith(
        phase: RecurringEventDetailPhase.ready,
        detail: detail,
        localizedEventTimeRange: localizedEventTimeRange,
        referenceLocalNow: referenceLocalNow,
        occurrences: List.unmodifiable(occurrences),
        hasMore: hasMore,
        nextCursor: nextCursor,
        isRefreshing: false,
        isLoadingMore: false,
        isDeleted: detail.event.deletedAt != null,
        loadFailure: null,
        paginationFailure: null,
      ),
    );
  }

  RecurringEventFailure _finishLoadFailure(
    int generation,
    bool preserveContent,
    RecurringEventFailure failure,
  ) {
    if (!_isCurrentLoad(generation)) return failure;
    if (preserveContent && _state.detail != null) {
      _emit(
        _state.copyWith(
          isRefreshing: false,
          isLoadingMore: false,
          loadFailure: failure,
        ),
      );
    } else {
      _activeQuery = null;
      _emit(
        RecurringEventDetailState.initial(
          focusOccurrenceKey: _state.focusOccurrenceKey,
        ).copyWith(
          phase: RecurringEventDetailPhase.failure,
          loadFailure: failure,
        ),
      );
    }
    return failure;
  }

  void _finishPaginationFailure(RecurringEventFailure failure) {
    _emit(_state.copyWith(isLoadingMore: false, paginationFailure: failure));
  }

  RecurringEventActionResult _finishOccurrenceFailure(
    String occurrenceKey,
    RecurringEventFailure failure,
  ) {
    final mutations = Map<String, RecurringEventOccurrenceMutation>.of(
      _state.occurrenceMutations,
    )..remove(occurrenceKey);
    _emit(
      _state.copyWith(
        occurrenceMutations: Map.unmodifiable(mutations),
        actionFailure: failure,
      ),
    );
    return RecurringEventActionResult.failure(failure);
  }

  void _finishOccurrenceSuccess(
    String occurrenceKey, {
    required RecurringEventFailure? warning,
  }) {
    final mutations = Map<String, RecurringEventOccurrenceMutation>.of(
      _state.occurrenceMutations,
    )..remove(occurrenceKey);
    _emit(
      _state.copyWith(
        occurrenceMutations: Map.unmodifiable(mutations),
        reconcileWarning: warning,
      ),
    );
  }

  RecurringEventActionResult _finishSeriesFailure(
    RecurringEventFailure failure,
  ) {
    _emit(_state.copyWith(seriesMutation: null, actionFailure: failure));
    return RecurringEventActionResult.failure(failure);
  }

  void _finishSeriesSuccess({required RecurringEventFailure? warning}) {
    _emit(_state.copyWith(seriesMutation: null, reconcileWarning: warning));
  }

  bool _isCurrentLoad(int generation) {
    return !_isDisposed && generation == _loadGeneration;
  }

  void _emit(RecurringEventDetailState state) {
    if (_isDisposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _loadGeneration += 1;
    super.dispose();
  }
}

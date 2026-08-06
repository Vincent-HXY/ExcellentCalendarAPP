import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/common/native_error_dto.dart';
import '../../native_contract/event/delete_event_request_dto.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/event_occurrence_operation_request_dto.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../../native_contract/event/event_occurrence_state_response_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/event_series_operation_request_dto.dart';
import '../../native_contract/event/get_event_detail_request_dto.dart';
import '../../native_contract/event/list_event_occurrences_request_dto.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../reminder/reconcile_reminder_schedule_use_case.dart';
import '../timezone/timezone_application_service.dart';

const Object _notProvided = Object();

enum RecurringEventDetailPhase { idle, loading, ready, failure }

enum RecurringEventOccurrenceMutation { complete, reopen, skip, cancel }

enum RecurringEventSeriesMutation { complete, reopen, cancel, delete }

enum RecurringEventActionOutcome { success, failure, ignored }

class RecurringEventFailure {
  const RecurringEventFailure({
    required this.message,
    this.code,
    this.retryable = false,
  });

  factory RecurringEventFailure.fromNativeError(NativeErrorDto? error) {
    return RecurringEventFailure(
      code: error?.code,
      message: error?.message ?? '操作失败，请稍后重试',
      retryable: error?.retryable ?? false,
    );
  }

  final String? code;
  final String message;
  final bool retryable;
}

class RecurringEventActionResult {
  const RecurringEventActionResult._({
    required this.outcome,
    this.failure,
    this.warning,
  });

  const RecurringEventActionResult.success({RecurringEventFailure? warning})
    : this._(outcome: RecurringEventActionOutcome.success, warning: warning);

  const RecurringEventActionResult.failure(RecurringEventFailure failure)
    : this._(outcome: RecurringEventActionOutcome.failure, failure: failure);

  RecurringEventActionResult.ignored(String message)
    : this._(
        outcome: RecurringEventActionOutcome.ignored,
        failure: RecurringEventFailure(message: message),
      );

  final RecurringEventActionOutcome outcome;
  final RecurringEventFailure? failure;
  final RecurringEventFailure? warning;

  bool get succeeded => outcome == RecurringEventActionOutcome.success;
  bool get wasIgnored => outcome == RecurringEventActionOutcome.ignored;
}

class RecurringEventOccurrenceItem {
  const RecurringEventOccurrenceItem({
    required this.occurrence,
    required this.localizedTimeRange,
  });

  final EventOccurrenceResponseDto occurrence;
  final LocalizedTimeRange localizedTimeRange;

  String get occurrenceKey => occurrence.occurrenceKey;
  String get status => occurrence.state?.status ?? 'scheduled';
}

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
       _gateway = gateway,
       _timezoneService = timezoneService,
       _reconcileReminderScheduleUseCase = reconcileReminderScheduleUseCase,
       _clock = clock ?? DateTime.now,
       _pastExtent = pastExtent,
       _futureExtent = futureExtent,
       _pageSize = pageSize,
       _state = RecurringEventDetailState.initial(
         focusOccurrenceKey: focusOccurrenceKey,
       ) {
    if (eventId.trim().isEmpty) {
      throw ArgumentError.value(eventId, 'eventId', 'must be non-empty');
    }
    if (pastExtent.isNegative || futureExtent <= Duration.zero) {
      throw ArgumentError('Occurrence query extents are invalid.');
    }
    if (pageSize < 1 || pageSize > 200) {
      throw RangeError.range(pageSize, 1, 200, 'pageSize');
    }
  }

  final String _eventId;
  final EventNativeGateway _gateway;
  final TimezoneApplicationService _timezoneService;
  final ReconcileReminderScheduleUseCase _reconcileReminderScheduleUseCase;
  final DateTime Function() _clock;
  final Duration _pastExtent;
  final Duration _futureExtent;
  final int _pageSize;

  RecurringEventDetailState _state;
  _OccurrenceQuery? _activeQuery;
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
      final invocation = await _gateway.listOccurrences(
        query.toRequest(cursor: cursor, limit: _pageSize),
      );
      if (!_isCurrentLoad(generation)) return;
      if (!invocation.result.ok || invocation.result.data == null) {
        _finishPaginationFailure(_failureFrom(invocation));
        return;
      }
      final response = invocation.result.data!;
      final projectionFailure = _validateOccurrences(
        response.items,
        detail: detail,
      );
      if (projectionFailure != null) {
        _finishPaginationFailure(projectionFailure);
        return;
      }
      final localized = await _timezoneService.localizeOccurrenceTimes(
        response.items,
      );
      if (!_isCurrentLoad(generation)) return;
      if (!localized.ok) {
        _finishPaginationFailure(
          RecurringEventFailure(
            code: localized.errorCode,
            message: localized.errorMessage ?? '无法按日程原时区显示更多日期',
          ),
        );
        return;
      }
      final newItemsFailure = _buildOccurrenceItems(
        response.items,
        localized.ranges,
      );
      if (newItemsFailure.failure != null) {
        _finishPaginationFailure(newItemsFailure.failure!);
        return;
      }
      final merged = <String, RecurringEventOccurrenceItem>{
        for (final item in _state.occurrences) item.occurrenceKey: item,
        for (final item in newItemsFailure.value!) item.occurrenceKey: item,
      };
      _emit(
        _state.copyWith(
          occurrences: List.unmodifiable(merged.values),
          hasMore: response.hasMore,
          nextCursor: response.nextCursor,
          isLoadingMore: false,
          paginationFailure: null,
        ),
      );
    } catch (_) {
      if (_isCurrentLoad(generation)) {
        _finishPaginationFailure(
          const RecurringEventFailure(message: '加载更多日程失败，请稍后重试'),
        );
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

  Future<RecurringEventActionResult> deleteSeries({String? reason}) async {
    final readinessFailure = _seriesReadinessFailure();
    if (readinessFailure != null) {
      return RecurringEventActionResult.failure(readinessFailure);
    }
    if (_state.hasMutationInProgress) {
      return RecurringEventActionResult.ignored('另一个重复日程操作正在进行');
    }

    final detail = _state.detail!;
    final revision = detail.recurrence!.revision;
    _emit(
      _state.copyWith(
        seriesMutation: RecurringEventSeriesMutation.delete,
        actionFailure: null,
      ),
    );
    try {
      final invocation = await _gateway.deleteEvent(
        DeleteEventRequestDto(
          id: _eventId,
          deleteMode: 'soft',
          recurrenceDeleteScope: 'all_occurrences',
          expectedRecurrenceRevision: revision,
          reason: reason,
        ),
      );
      if (!invocation.result.ok || invocation.result.data == null) {
        return _finishSeriesFailure(_failureFrom(invocation));
      }
      final deletedEvent = invocation.result.data!;
      if (!_matchesSeriesIdentity(deletedEvent, detail.event) ||
          deletedEvent.deletedAt == null) {
        return _finishSeriesFailure(
          const RecurringEventFailure(message: 'Native 删除结果与当前重复日程不一致'),
        );
      }

      _loadGeneration += 1;
      _activeQuery = null;
      _emit(
        _state.copyWith(
          detail: _detailWithEvent(detail, deletedEvent),
          occurrences: const [],
          hasMore: false,
          nextCursor: null,
          isDeleted: true,
          actionFailure: null,
        ),
      );
      final warning = await _reconcileAfterMutation();
      _finishSeriesSuccess(warning: warning);
      return RecurringEventActionResult.success(warning: warning);
    } catch (_) {
      return _finishSeriesFailure(
        const RecurringEventFailure(message: '删除重复日程失败，请稍后重试'),
      );
    }
  }

  Future<RecurringEventFailure?> _load({required bool preserveContent}) async {
    final generation = ++_loadGeneration;
    final nowUtc = _wholeSecondUtc(_clock());
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
      final detailInvocation = await _gateway.getEventDetail(
        GetEventDetailRequestDto(id: _eventId),
      );
      if (!_isCurrentLoad(generation)) return null;
      if (!detailInvocation.result.ok || detailInvocation.result.data == null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          _failureFrom(detailInvocation),
        );
      }
      final detail = detailInvocation.result.data!;
      if (detail.event.id != _eventId) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          const RecurringEventFailure(message: 'Native 返回了其他日程的详情'),
        );
      }

      final localizedEvent = await _timezoneService.localizeEventTimes([
        detail.event,
      ]);
      if (!_isCurrentLoad(generation)) return null;
      if (!localizedEvent.ok ||
          localizedEvent.ranges[detail.event.id] == null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          RecurringEventFailure(
            code: localizedEvent.errorCode,
            message: localizedEvent.errorMessage ?? '无法按日程原时区显示时间',
          ),
        );
      }

      final referenceNowInvocation = await _timezoneService.localizeInstants(
        timezone: detail.event.timezone,
        instants: [nowUtc],
      );
      if (!_isCurrentLoad(generation)) return null;
      if (!referenceNowInvocation.result.ok ||
          referenceNowInvocation.result.data == null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          _failureFrom(referenceNowInvocation),
        );
      }
      final localizedNow = referenceNowInvocation.result.data!;
      if (localizedNow.timezone != detail.event.timezone ||
          localizedNow.items.length != 1 ||
          !localizedNow.items.single.instant.isAtSameMomentAs(nowUtc)) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          const RecurringEventFailure(message: 'Native 返回的原时区当前时间不一致'),
        );
      }
      final referenceLocalNow = localizedNow.items.single.localDateTime;

      if (detail.recurrence == null) {
        _activeQuery = null;
        _commitLoaded(
          detail: detail,
          localizedEventTimeRange: localizedEvent.ranges[detail.event.id]!,
          referenceLocalNow: referenceLocalNow,
          occurrences: const [],
          hasMore: false,
          nextCursor: null,
        );
        return null;
      }

      final query = _OccurrenceQuery.forEvent(
        detail.event,
        nowUtc: nowUtc,
        referenceLocalNow: referenceLocalNow,
        pastExtent: _pastExtent,
        futureExtent: _futureExtent,
      );
      final occurrenceInvocation = await _gateway.listOccurrences(
        query.toRequest(limit: _pageSize),
      );
      if (!_isCurrentLoad(generation)) return null;
      if (!occurrenceInvocation.result.ok ||
          occurrenceInvocation.result.data == null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          _failureFrom(occurrenceInvocation),
        );
      }
      final occurrenceResponse = occurrenceInvocation.result.data!;
      final projectionFailure = _validateOccurrences(
        occurrenceResponse.items,
        detail: detail,
      );
      if (projectionFailure != null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          projectionFailure,
        );
      }
      if (occurrenceResponse.hasMore && occurrenceResponse.nextCursor == null) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          const RecurringEventFailure(
            message: 'Native 返回了无法继续分页的 occurrence 列表',
          ),
        );
      }

      final localizedOccurrences = await _timezoneService
          .localizeOccurrenceTimes(occurrenceResponse.items);
      if (!_isCurrentLoad(generation)) return null;
      if (!localizedOccurrences.ok) {
        return _finishLoadFailure(
          generation,
          preserveContent,
          RecurringEventFailure(
            code: localizedOccurrences.errorCode,
            message:
                localizedOccurrences.errorMessage ?? '无法按日程原时区显示 occurrence',
          ),
        );
      }
      final items = _buildOccurrenceItems(
        occurrenceResponse.items,
        localizedOccurrences.ranges,
      );
      if (items.failure != null) {
        return _finishLoadFailure(generation, preserveContent, items.failure!);
      }

      _activeQuery = query;
      _commitLoaded(
        detail: detail,
        localizedEventTimeRange: localizedEvent.ranges[detail.event.id]!,
        referenceLocalNow: referenceLocalNow,
        occurrences: items.value!,
        hasMore: occurrenceResponse.hasMore,
        nextCursor: occurrenceResponse.nextCursor,
      );
      return null;
    } catch (_) {
      if (!_isCurrentLoad(generation)) return null;
      return _finishLoadFailure(
        generation,
        preserveContent,
        const RecurringEventFailure(message: '加载日程详情失败，请稍后重试'),
      );
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
    final request = item.occurrence.occurrenceStartAt != null
        ? EventOccurrenceOperationRequestDto.timed(
            eventId: _eventId,
            recurrenceRevision: detail.recurrence!.revision,
            occurrenceKey: occurrenceKey,
            occurrenceStartAt: item.occurrence.occurrenceStartAt!,
          )
        : EventOccurrenceOperationRequestDto.allDay(
            eventId: _eventId,
            recurrenceRevision: detail.recurrence!.revision,
            occurrenceKey: occurrenceKey,
            occurrenceStartDate: item.occurrence.occurrenceStartDate!,
          );
    try {
      final invocation = await switch (mutation) {
        RecurringEventOccurrenceMutation.complete =>
          _gateway.completeOccurrence(request),
        RecurringEventOccurrenceMutation.reopen => _gateway.reopenOccurrence(
          request,
        ),
        RecurringEventOccurrenceMutation.skip => _gateway.skipOccurrence(
          request,
        ),
        RecurringEventOccurrenceMutation.cancel => _gateway.cancelOccurrence(
          request,
        ),
      };
      if (!invocation.result.ok || invocation.result.data == null) {
        return _finishOccurrenceFailure(
          occurrenceKey,
          _failureFrom(invocation),
        );
      }
      final stateResponse = invocation.result.data!;
      final responseFailure = _validateOccurrenceMutationResponse(
        stateResponse,
        item.occurrence,
        mutation,
      );
      if (responseFailure != null) {
        return _finishOccurrenceFailure(occurrenceKey, responseFailure);
      }

      final updatedItems = _state.occurrences
          .map(
            (current) => current.occurrenceKey == occurrenceKey
                ? RecurringEventOccurrenceItem(
                    occurrence: _occurrenceWithState(
                      current.occurrence,
                      stateResponse,
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
      final warning = await _reconcileAfterMutation();
      _finishOccurrenceSuccess(occurrenceKey, warning: warning);
      return RecurringEventActionResult.success(warning: warning);
    } catch (_) {
      return _finishOccurrenceFailure(
        occurrenceKey,
        const RecurringEventFailure(message: '更新 occurrence 失败，请稍后重试'),
      );
    }
  }

  Future<RecurringEventActionResult> _mutateSeries(
    RecurringEventSeriesMutation mutation,
  ) async {
    final readinessFailure = _seriesReadinessFailure();
    if (readinessFailure != null) {
      return RecurringEventActionResult.failure(readinessFailure);
    }
    if (_state.hasMutationInProgress) {
      return RecurringEventActionResult.ignored('另一个重复日程操作正在进行');
    }

    final detail = _state.detail!;
    final request = EventSeriesOperationRequestDto(
      eventId: _eventId,
      recurrenceRevision: detail.recurrence!.revision,
    );
    _emit(_state.copyWith(seriesMutation: mutation, actionFailure: null));
    try {
      final invocation = await switch (mutation) {
        RecurringEventSeriesMutation.complete => _gateway.completeSeries(
          request,
        ),
        RecurringEventSeriesMutation.reopen => _gateway.reopenSeries(request),
        RecurringEventSeriesMutation.cancel => _gateway.cancelSeries(request),
        RecurringEventSeriesMutation.delete => throw StateError(
          'delete uses deleteSeries',
        ),
      };
      if (!invocation.result.ok || invocation.result.data == null) {
        return _finishSeriesFailure(_failureFrom(invocation));
      }
      final event = invocation.result.data!;
      final expectedStatus = switch (mutation) {
        RecurringEventSeriesMutation.complete => 'completed',
        RecurringEventSeriesMutation.reopen => 'active',
        RecurringEventSeriesMutation.cancel => 'cancelled',
        RecurringEventSeriesMutation.delete => '',
      };
      if (!_matchesSeriesIdentity(event, detail.event) ||
          event.status != expectedStatus) {
        return _finishSeriesFailure(
          const RecurringEventFailure(message: 'Native 系列操作结果与当前重复日程不一致'),
        );
      }
      _emit(
        _state.copyWith(
          detail: _detailWithEvent(_state.detail ?? detail, event),
          actionFailure: null,
        ),
      );
      final warning = await _reconcileAfterMutation();
      final refreshFailure = await _load(preserveContent: true);
      _finishSeriesSuccess(warning: warning);
      return RecurringEventActionResult.success(
        warning: warning ?? refreshFailure,
      );
    } catch (_) {
      return _finishSeriesFailure(
        const RecurringEventFailure(message: '更新重复系列失败，请稍后重试'),
      );
    }
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

  Future<RecurringEventFailure?> _reconcileAfterMutation() async {
    try {
      final invocation = await _reconcileReminderScheduleUseCase.execute(
        triggerSource: ReminderScheduleTrigger.mutation,
        force: true,
      );
      if (!invocation.result.ok || invocation.result.data == null) {
        return _failureFrom(invocation);
      }
      final response = invocation.result.data!;
      if (response.failedCount > 0) {
        return RecurringEventFailure(
          message: '${response.failedCount} 条提醒暂时调度失败，稍后会继续恢复',
          retryable: true,
        );
      }
      return null;
    } catch (_) {
      return const RecurringEventFailure(
        message: '日程已更新，但提醒调度恢复失败',
        retryable: true,
      );
    }
  }

  RecurringEventFailure? _validateOccurrences(
    List<EventOccurrenceResponseDto> occurrences, {
    required EventDetailResponseDto detail,
  }) {
    final recurrence = detail.recurrence!;
    final seen = <String>{};
    for (final occurrence in occurrences) {
      if (occurrence.eventId != detail.event.id ||
          occurrence.recurrenceRevision != recurrence.revision ||
          occurrence.timezone != detail.event.timezone ||
          !seen.add(occurrence.occurrenceKey)) {
        return const RecurringEventFailure(
          message: 'Native occurrence 投影与当前重复日程不一致',
        );
      }
    }
    return null;
  }

  _ValueOrFailure<List<RecurringEventOccurrenceItem>> _buildOccurrenceItems(
    List<EventOccurrenceResponseDto> occurrences,
    Map<String, LocalizedTimeRange> localizedRanges,
  ) {
    final items = <RecurringEventOccurrenceItem>[];
    for (final occurrence in occurrences) {
      final range = localizedRanges[occurrence.occurrenceKey];
      if (range == null || range.timezone != occurrence.timezone) {
        return const _ValueOrFailure.failure(
          RecurringEventFailure(message: 'occurrence 缺少原时区显示时间'),
        );
      }
      items.add(
        RecurringEventOccurrenceItem(
          occurrence: occurrence,
          localizedTimeRange: range,
        ),
      );
    }
    return _ValueOrFailure.value(List.unmodifiable(items));
  }

  RecurringEventFailure? _validateOccurrenceMutationResponse(
    EventOccurrenceStateResponseDto response,
    EventOccurrenceResponseDto occurrence,
    RecurringEventOccurrenceMutation mutation,
  ) {
    final expectedStatus = switch (mutation) {
      RecurringEventOccurrenceMutation.complete => 'completed',
      RecurringEventOccurrenceMutation.reopen => 'scheduled',
      RecurringEventOccurrenceMutation.skip => 'skipped',
      RecurringEventOccurrenceMutation.cancel => 'cancelled',
    };
    final sameStart =
        (occurrence.occurrenceStartAt != null &&
            response.occurrenceStartAt != null &&
            occurrence.occurrenceStartAt!.isAtSameMomentAs(
              response.occurrenceStartAt!,
            )) ||
        (occurrence.occurrenceStartDate != null &&
            occurrence.occurrenceStartDate == response.occurrenceStartDate);
    if (response.eventId != occurrence.eventId ||
        response.recurrenceRevision != occurrence.recurrenceRevision ||
        response.occurrenceKey != occurrence.occurrenceKey ||
        !sameStart ||
        response.status != expectedStatus) {
      return const RecurringEventFailure(
        message: 'Native occurrence 操作结果与请求不一致',
      );
    }
    return null;
  }

  bool _matchesSeriesIdentity(
    EventResponseDto response,
    EventResponseDto current,
  ) {
    return response.id == current.id &&
        response.hasRecurrence &&
        response.recurrenceId == current.recurrenceId &&
        response.recurrenceRevision == current.recurrenceRevision;
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

  RecurringEventFailure _failureFrom<T>(NativeInvocation<T> invocation) {
    return RecurringEventFailure.fromNativeError(invocation.result.error);
  }

  bool _isCurrentLoad(int generation) {
    return !_isDisposed && generation == _loadGeneration;
  }

  void _emit(RecurringEventDetailState state) {
    if (_isDisposed) return;
    _state = state;
    notifyListeners();
  }

  static DateTime _wholeSecondUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _loadGeneration += 1;
    super.dispose();
  }
}

class _OccurrenceQuery {
  const _OccurrenceQuery.timed({
    required this.eventId,
    required this.recurrenceRevision,
    required this.rangeStartAt,
    required this.rangeEndAt,
  }) : rangeStartDate = null,
       rangeEndDate = null;

  const _OccurrenceQuery.allDay({
    required this.eventId,
    required this.recurrenceRevision,
    required this.rangeStartDate,
    required this.rangeEndDate,
  }) : rangeStartAt = null,
       rangeEndAt = null;

  factory _OccurrenceQuery.forEvent(
    EventResponseDto event, {
    required DateTime nowUtc,
    required LocalWallDateTime referenceLocalNow,
    required Duration pastExtent,
    required Duration futureExtent,
  }) {
    if (!event.isAllDay) {
      return _OccurrenceQuery.timed(
        eventId: event.id,
        recurrenceRevision: event.recurrenceRevision!,
        rangeStartAt: RecurringEventDetailController._wholeSecondUtc(
          nowUtc.subtract(pastExtent),
        ),
        rangeEndAt: RecurringEventDetailController._wholeSecondUtc(
          nowUtc.add(futureExtent),
        ),
      );
    }
    final anchor = DateTime.utc(
      referenceLocalNow.year,
      referenceLocalNow.month,
      referenceLocalNow.day,
    );
    final start = anchor.subtract(Duration(days: _ceilDays(pastExtent)));
    final end = anchor.add(Duration(days: _ceilDays(futureExtent)));
    return _OccurrenceQuery.allDay(
      eventId: event.id,
      recurrenceRevision: event.recurrenceRevision!,
      rangeStartDate: _formatLocalDate(start),
      rangeEndDate: _formatLocalDate(end),
    );
  }

  final String eventId;
  final int recurrenceRevision;
  final DateTime? rangeStartAt;
  final DateTime? rangeEndAt;
  final String? rangeStartDate;
  final String? rangeEndDate;

  ListEventOccurrencesRequestDto toRequest({
    String? cursor,
    required int limit,
  }) {
    if (rangeStartAt != null) {
      return ListEventOccurrencesRequestDto.timed(
        eventId: eventId,
        recurrenceRevision: recurrenceRevision,
        rangeStartAt: rangeStartAt!,
        rangeEndAt: rangeEndAt!,
        cursor: cursor,
        limit: limit,
      );
    }
    return ListEventOccurrencesRequestDto.allDay(
      eventId: eventId,
      recurrenceRevision: recurrenceRevision,
      rangeStartDate: rangeStartDate!,
      rangeEndDate: rangeEndDate!,
      cursor: cursor,
      limit: limit,
    );
  }

  static int _ceilDays(Duration duration) {
    if (duration == Duration.zero) return 0;
    const dayMicros = Duration.microsecondsPerDay;
    return (duration.inMicroseconds + dayMicros - 1) ~/ dayMicros;
  }

  static String _formatLocalDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

class _ValueOrFailure<T> {
  const _ValueOrFailure.value(this.value) : failure = null;
  const _ValueOrFailure.failure(this.failure) : value = null;

  final T? value;
  final RecurringEventFailure? failure;
}

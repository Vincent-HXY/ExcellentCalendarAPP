import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/calendar_gateway.dart';
import '../../native_contract/calendar/calendar_contract_enums.dart';
import '../../native_contract/calendar/calendar_request_dtos.dart';
import '../../native_contract/calendar/calendar_response_dtos.dart';
import 'calendar_date_math.dart';
import 'calendar_models.dart';

typedef CalendarTimezoneProvider = Future<String> Function();
typedef CalendarNowProvider = DateTime Function();

class CalendarController extends ChangeNotifier {
  CalendarController({
    required CalendarGateway gateway,
    required CalendarTimezoneProvider timezoneProvider,
    CalendarNowProvider? nowProvider,
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider,
       _nowProvider = nowProvider ?? DateTime.now,
       _state = CalendarState.initial((nowProvider ?? DateTime.now)());

  static const pageSize = 20;

  final CalendarGateway _gateway;
  final CalendarTimezoneProvider _timezoneProvider;
  final CalendarNowProvider _nowProvider;
  final Map<_RangeCacheKey, CalendarRangeSummaryResponseDto> _rangeCache = {};
  final Map<_DayCacheKey, CalendarDayItemPageDto> _dayCache = {};
  final Map<CalendarSection, int> _loadMoreInFlight = {};

  CalendarState _state;
  int _generation = 0;
  bool _disposed = false;
  bool _initialized = false;
  bool _active = true;
  bool _routeNeedsReload = false;
  int _loadMoreRequestId = 0;

  CalendarState get state => _state;
  bool get isDisposed => _disposed;

  Future<void> initialize({
    CalendarViewMode initialViewMode = CalendarViewMode.week,
  }) async {
    if (_initialized || _disposed) return;
    _initialized = true;
    final today = CalendarDateMath.dateOnly(_nowProvider());
    final range = CalendarDateMath.visibleRange(today, initialViewMode);
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        selectedDate: today,
        anchorDate: today,
        today: today,
        visibleRangeStart: range.start,
        visibleRangeEnd: range.end,
        viewMode: initialViewMode,
        isCollapsed: initialViewMode == CalendarViewMode.week,
        rangePhase: CalendarRangePhase.loading,
        eventSection: _loadingSection(CalendarSection.event),
        habitSection: _loadingSection(CalendarSection.habit),
        anniversarySection: _loadingSection(CalendarSection.anniversary),
        errorMessage: null,
        generation: generation,
      ),
    );
    try {
      final timezone = await _timezoneProvider();
      if (!_isCurrent(generation)) return;
      if (timezone.trim().isEmpty || timezone.length > 255) {
        throw const FormatException('Device IANA timezone is unavailable.');
      }
      _setState(_state.copyWith(timezone: timezone));
      await _loadFull(generation: generation, allowCache: true);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _commitFailure(error, preserveSnapshot: false);
    }
  }

  Future<void> setActive(bool value) async {
    if (_disposed || value == _active) return;
    _active = value;
    final generation = _nextGeneration();
    _setState(_state.copyWith(generation: generation));
    if (!value || !_initialized) return;
    await _reloadAfterActivation(generation);
  }

  Future<void> _reloadAfterActivation(int generation) async {
    final preserveCurrent = _state.hasCompleteSnapshot;
    try {
      final timezone = await _timezoneProvider();
      if (!_isCurrent(generation)) return;
      if (timezone.trim().isEmpty || timezone.length > 255) {
        throw const FormatException('Device IANA timezone is unavailable.');
      }
      final today = CalendarDateMath.dateOnly(_nowProvider());
      final temporalContextChanged =
          timezone != _state.timezone ||
          !CalendarDateMath.isSameDate(today, _state.today);
      if (temporalContextChanged) {
        _invalidateCaches();
        _setState(
          _state.copyWith(
            timezone: timezone,
            today: today,
            rangePhase: CalendarRangePhase.refreshing,
            snapshotToken: null,
            eventSection: _invalidateSectionCursor(_state.eventSection),
            habitSection: _invalidateSectionCursor(_state.habitSection),
            anniversarySection: _invalidateSectionCursor(
              _state.anniversarySection,
            ),
            errorMessage: null,
            generation: generation,
          ),
        );
      }
      await _loadFull(
        generation: generation,
        allowCache: !temporalContextChanged,
        preserveCurrent: preserveCurrent,
      );
    } catch (error) {
      if (_isCurrent(generation)) {
        _commitFailure(error, preserveSnapshot: preserveCurrent);
      }
    }
  }

  Future<void> selectDate(DateTime value) async {
    if (!_canInteract) return;
    final date = CalendarDateMath.dateOnly(value);
    if (CalendarDateMath.isSameDate(date, _state.selectedDate)) return;
    final changesMonth =
        _state.viewMode == CalendarViewMode.month &&
        (date.year != _state.anchorDate.year ||
            date.month != _state.anchorDate.month);
    final outsideRange = !_state.visibleRange.contains(date);
    if (changesMonth || outsideRange) {
      await _transitionToDate(date, forceNewRange: true);
      return;
    }

    final generation = _nextGeneration();
    final cachedPages = _cachedPages(
      date: date,
      snapshotToken: _state.snapshotToken,
    );
    _setState(
      _state.copyWith(
        selectedDate: date,
        anchorDate: _state.viewMode == CalendarViewMode.week
            ? date
            : _state.anchorDate,
        rangePhase: CalendarRangePhase.refreshing,
        eventSection: _sectionFromCacheOrLoading(
          CalendarSection.event,
          cachedPages,
        ),
        habitSection: _sectionFromCacheOrLoading(
          CalendarSection.habit,
          cachedPages,
        ),
        anniversarySection: _sectionFromCacheOrLoading(
          CalendarSection.anniversary,
          cachedPages,
        ),
        errorMessage: null,
        showingCachedSnapshot: cachedPages != null,
        generation: generation,
      ),
    );
    if (cachedPages != null) {
      _setState(
        _state.copyWith(
          rangePhase: CalendarRangePhase.refreshing,
          eventSection: _state.eventSection.copyWith(
            phase: CalendarSectionPhase.refreshing,
          ),
          habitSection: _state.habitSection.copyWith(
            phase: CalendarSectionPhase.refreshing,
          ),
          anniversarySection: _state.anniversarySection.copyWith(
            phase: CalendarSectionPhase.refreshing,
          ),
        ),
      );
    }
    await _loadSelectedDay(
      generation: generation,
      snapshotToken: _state.snapshotToken,
      preserveCurrent: cachedPages != null,
    );
  }

  Future<void> setViewMode(CalendarViewMode mode) async {
    if (!_canInteract || mode == _state.viewMode) return;
    final range = CalendarDateMath.visibleRange(_state.selectedDate, mode);
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        anchorDate: _state.selectedDate,
        viewMode: mode,
        isCollapsed: mode == CalendarViewMode.week,
        visibleRangeStart: range.start,
        visibleRangeEnd: range.end,
        rangePhase: CalendarRangePhase.loading,
        rangeDays: const [],
        snapshotToken: null,
        eventSection: _loadingSection(CalendarSection.event),
        habitSection: _loadingSection(CalendarSection.habit),
        anniversarySection: _loadingSection(CalendarSection.anniversary),
        errorMessage: null,
        generation: generation,
      ),
    );
    await _loadFull(generation: generation, allowCache: true);
  }

  Future<void> navigatePeriod(int delta) async {
    if (!_canInteract || delta == 0) return;
    final target = switch (_state.viewMode) {
      CalendarViewMode.week => _state.selectedDate.add(
        Duration(days: 7 * delta),
      ),
      CalendarViewMode.month => CalendarDateMath.addMonthsClamped(
        _state.selectedDate,
        delta,
      ),
    };
    await _transitionToDate(target, forceNewRange: true);
  }

  Future<void> jumpToMonth({required int year, required int month}) async {
    if (!_canInteract || month < 1 || month > 12) return;
    final target = CalendarDateMath.inMonthKeepingDay(
      year: year,
      month: month,
      preferredDay: _state.selectedDate.day,
    );
    await _transitionToDate(target, forceNewRange: true);
  }

  Future<void> goToToday() async {
    if (!_canInteract) return;
    final today = CalendarDateMath.dateOnly(_nowProvider());
    await _transitionToDate(today, forceNewRange: true, today: today);
  }

  Future<void> refresh() async {
    if (!_canInteract) return;
    final preserveCurrent = _state.hasCompleteSnapshot;
    _invalidateCaches();
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        rangePhase: preserveCurrent
            ? CalendarRangePhase.refreshing
            : CalendarRangePhase.loading,
        snapshotToken: null,
        eventSection: _invalidateSectionCursor(_state.eventSection),
        habitSection: _invalidateSectionCursor(_state.habitSection),
        anniversarySection: _invalidateSectionCursor(_state.anniversarySection),
        errorMessage: null,
        showingCachedSnapshot: false,
        generation: generation,
      ),
    );
    await _loadFull(
      generation: generation,
      allowCache: false,
      preserveCurrent: preserveCurrent,
    );
  }

  Future<void> handleRouteResult(bool changed) async {
    if (changed) {
      _routeNeedsReload = false;
      await refresh();
      return;
    }
    if (!_routeNeedsReload || !_canInteract) return;
    _routeNeedsReload = false;
    final preserveCurrent = _state.rangeDays.isNotEmpty;
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        rangePhase: preserveCurrent
            ? CalendarRangePhase.refreshing
            : CalendarRangePhase.loading,
        eventSection: _refreshingOrLoading(_state.eventSection),
        habitSection: _refreshingOrLoading(_state.habitSection),
        anniversarySection: _refreshingOrLoading(_state.anniversarySection),
        generation: generation,
      ),
    );
    await _loadFull(
      generation: generation,
      allowCache: true,
      preserveCurrent: preserveCurrent,
    );
  }

  void beginRouteTransition() {
    if (!_canInteract) return;
    _routeNeedsReload =
        _state.snapshotToken == null || _state.rangeDays.isEmpty;
    _loadMoreInFlight.clear();
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        rangePhase: _state.snapshotToken != null && _state.rangeDays.isNotEmpty
            ? CalendarRangePhase.ready
            : _state.rangePhase,
        eventSection: _settleInterruptedSection(_state.eventSection),
        habitSection: _settleInterruptedSection(_state.habitSection),
        anniversarySection: _settleInterruptedSection(
          _state.anniversarySection,
        ),
        generation: generation,
      ),
    );
  }

  Future<void> handleMidnight() async {
    if (!_canInteract) return;
    final today = CalendarDateMath.dateOnly(_nowProvider());
    if (CalendarDateMath.isSameDate(today, _state.today)) return;
    final preserveCurrent = _state.hasCompleteSnapshot;
    _invalidateCaches();
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        today: today,
        rangePhase: CalendarRangePhase.refreshing,
        snapshotToken: null,
        eventSection: _invalidateSectionCursor(_state.eventSection),
        habitSection: _invalidateSectionCursor(_state.habitSection),
        anniversarySection: _invalidateSectionCursor(_state.anniversarySection),
        errorMessage: null,
        generation: generation,
      ),
    );
    await _loadFull(
      generation: generation,
      allowCache: false,
      preserveCurrent: preserveCurrent,
    );
  }

  Future<void> reconcileTemporalContext() async {
    if (!_canInteract) return;
    try {
      final timezone = await _timezoneProvider();
      if (_disposed || !_active) return;
      if (timezone != _state.timezone) {
        await changeTimezone(timezone);
        return;
      }
      await handleMidnight();
    } catch (_) {
      // A transient resume probe must not replace a complete visible snapshot.
    }
  }

  Future<void> changeTimezone(String timezone) async {
    if (_disposed || !_initialized || timezone == _state.timezone) return;
    if (timezone.trim().isEmpty || timezone.length > 255) {
      _commitFailure(
        const FormatException('Device IANA timezone is unavailable.'),
        preserveSnapshot: _state.hasCompleteSnapshot,
      );
      return;
    }
    final preserveCurrent = _state.hasCompleteSnapshot;
    _invalidateCaches();
    final today = CalendarDateMath.dateOnly(_nowProvider());
    final range = CalendarDateMath.visibleRange(
      _state.anchorDate,
      _state.viewMode,
    );
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        timezone: timezone,
        today: today,
        visibleRangeStart: range.start,
        visibleRangeEnd: range.end,
        rangePhase: CalendarRangePhase.refreshing,
        snapshotToken: null,
        eventSection: _invalidateSectionCursor(_state.eventSection),
        habitSection: _invalidateSectionCursor(_state.habitSection),
        anniversarySection: _invalidateSectionCursor(_state.anniversarySection),
        errorMessage: null,
        generation: generation,
      ),
    );
    await _loadFull(
      generation: generation,
      allowCache: false,
      preserveCurrent: preserveCurrent,
    );
  }

  Future<void> loadMore(CalendarSection section) async {
    if (!_canInteract || _loadMoreInFlight.containsKey(section)) return;
    final current = _state.section(section);
    final token = _state.snapshotToken;
    final cursor = current.nextCursor;
    if (!current.hasMore || token == null || cursor == null) return;
    final requestId = ++_loadMoreRequestId;
    _loadMoreInFlight[section] = requestId;
    final generation = _generation;
    _setState(
      _state.withSection(
        current.copyWith(
          phase: CalendarSectionPhase.loadingMore,
          errorMessage: null,
        ),
      ),
    );
    try {
      final page = await _gateway.listDayItems(
        CalendarListDayItemsRequestDto(
          date: CalendarDateMath.formatDate(_state.selectedDate),
          timezone: _state.timezone,
          section: section,
          snapshotToken: token,
          cursor: cursor,
          pageSize: pageSize,
        ),
      );
      if (!_isCurrent(generation) || _state.snapshotToken != token) return;
      final identities = current.items.map((item) => item.identityKey).toSet();
      for (final item in page.items) {
        if (!identities.add(item.identityKey)) {
          throw const FormatException(
            'Calendar pagination returned a duplicate identity.',
          );
        }
      }
      _setState(
        _state.withSection(
          current.copyWith(
            phase: CalendarSectionPhase.ready,
            items: [...current.items, ...page.items],
            hasMore: page.hasMore,
            nextCursor: page.nextCursor,
            errorMessage: null,
          ),
        ),
      );
    } on CalendarGatewayFailure catch (error) {
      if (!_isCurrent(generation)) return;
      if (error.isSnapshotExpired) {
        await refresh();
      } else {
        _setState(
          _state.withSection(
            current.copyWith(
              phase: CalendarSectionPhase.error,
              errorMessage: _messageFor(error),
            ),
          ),
        );
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _setState(
          _state.withSection(
            current.copyWith(
              phase: CalendarSectionPhase.error,
              errorMessage: _messageFor(error),
            ),
          ),
        );
      }
    } finally {
      if (_loadMoreInFlight[section] == requestId) {
        _loadMoreInFlight.remove(section);
      }
    }
  }

  Future<void> retryLoadMore(CalendarSection section) => loadMore(section);

  Future<void> _transitionToDate(
    DateTime value, {
    required bool forceNewRange,
    DateTime? today,
  }) async {
    final date = CalendarDateMath.dateOnly(value);
    final range = CalendarDateMath.visibleRange(date, _state.viewMode);
    final generation = _nextGeneration();
    _setState(
      _state.copyWith(
        selectedDate: date,
        anchorDate: date,
        today: today,
        visibleRangeStart: range.start,
        visibleRangeEnd: range.end,
        rangePhase: CalendarRangePhase.loading,
        rangeDays: const [],
        snapshotToken: null,
        eventSection: _loadingSection(CalendarSection.event),
        habitSection: _loadingSection(CalendarSection.habit),
        anniversarySection: _loadingSection(CalendarSection.anniversary),
        errorMessage: null,
        showingCachedSnapshot: false,
        generation: generation,
      ),
    );
    await _loadFull(generation: generation, allowCache: true);
  }

  Future<void> _loadFull({
    required int generation,
    required bool allowCache,
    bool preserveCurrent = false,
    int snapshotRetry = 0,
  }) async {
    if (!_isCurrent(generation)) return;
    final request = CalendarRangeSummaryRequestDto(
      rangeStartDate: CalendarDateMath.formatDate(_state.visibleRangeStart),
      rangeEndDate: CalendarDateMath.formatDate(_state.visibleRangeEnd),
      timezone: _state.timezone,
    );
    final rangeKey = _RangeCacheKey.fromRequest(request);
    if (allowCache) {
      final cachedRange = _rangeCache[rangeKey];
      final cachedPages = cachedRange == null
          ? null
          : _cachedPages(
              date: _state.selectedDate,
              snapshotToken: cachedRange.snapshotToken,
            );
      if (cachedRange != null && cachedPages != null) {
        _commitSnapshot(
          generation: generation,
          range: cachedRange,
          pages: cachedPages,
          fromCache: true,
        );
        if (!_isCurrent(generation)) return;
        _setState(
          _state.copyWith(
            rangePhase: CalendarRangePhase.refreshing,
            eventSection: _state.eventSection.copyWith(
              phase: CalendarSectionPhase.refreshing,
            ),
            habitSection: _state.habitSection.copyWith(
              phase: CalendarSectionPhase.refreshing,
            ),
            anniversarySection: _state.anniversarySection.copyWith(
              phase: CalendarSectionPhase.refreshing,
            ),
          ),
        );
        preserveCurrent = true;
      }
    }
    try {
      final range = await _gateway.rangeSummary(request);
      if (!_isCurrent(generation)) return;
      final pages = await _fetchFirstPages(
        date: _state.selectedDate,
        timezone: request.timezone,
        snapshotToken: range.snapshotToken,
      );
      if (!_isCurrent(generation)) return;
      _rangeCache[rangeKey] = range;
      for (final entry in pages.entries) {
        _dayCache[_DayCacheKey(
              timezone: request.timezone,
              date: CalendarDateMath.formatDate(_state.selectedDate),
              section: entry.key,
            )] =
            entry.value;
      }
      _commitSnapshot(
        generation: generation,
        range: range,
        pages: pages,
        fromCache: false,
      );
    } on CalendarGatewayFailure catch (error) {
      if (!_isCurrent(generation)) return;
      if (error.isSnapshotExpired && snapshotRetry < 1) {
        _invalidateCaches();
        await _loadFull(
          generation: generation,
          allowCache: false,
          preserveCurrent: preserveCurrent,
          snapshotRetry: snapshotRetry + 1,
        );
        return;
      }
      _commitFailure(error, preserveSnapshot: preserveCurrent);
    } catch (error) {
      if (_isCurrent(generation)) {
        _commitFailure(error, preserveSnapshot: preserveCurrent);
      }
    }
  }

  Future<void> _loadSelectedDay({
    required int generation,
    required String? snapshotToken,
    bool preserveCurrent = false,
  }) async {
    if (snapshotToken == null) {
      await _loadFull(generation: generation, allowCache: false);
      return;
    }
    try {
      final pages = await _fetchFirstPages(
        date: _state.selectedDate,
        timezone: _state.timezone,
        snapshotToken: snapshotToken,
      );
      if (!_isCurrent(generation) || _state.snapshotToken != snapshotToken) {
        return;
      }
      for (final entry in pages.entries) {
        _dayCache[_DayCacheKey(
              timezone: _state.timezone,
              date: CalendarDateMath.formatDate(_state.selectedDate),
              section: entry.key,
            )] =
            entry.value;
      }
      _setState(
        _state.copyWith(
          rangePhase: CalendarRangePhase.ready,
          eventSection: _readySection(pages[CalendarSection.event]!),
          habitSection: _readySection(pages[CalendarSection.habit]!),
          anniversarySection: _readySection(
            pages[CalendarSection.anniversary]!,
          ),
          errorMessage: null,
          showingCachedSnapshot: false,
        ),
      );
    } on CalendarGatewayFailure catch (error) {
      if (!_isCurrent(generation)) return;
      if (error.isSnapshotExpired) {
        _invalidateCaches();
        _setState(
          _state.copyWith(
            rangePhase: CalendarRangePhase.refreshing,
            snapshotToken: null,
            eventSection: _invalidateSectionCursor(_state.eventSection),
            habitSection: _invalidateSectionCursor(_state.habitSection),
            anniversarySection: _invalidateSectionCursor(
              _state.anniversarySection,
            ),
          ),
        );
        await _loadFull(
          generation: generation,
          allowCache: false,
          preserveCurrent: preserveCurrent,
        );
      } else {
        _commitFailure(error, preserveSnapshot: preserveCurrent);
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        _commitFailure(error, preserveSnapshot: preserveCurrent);
      }
    }
  }

  Future<Map<CalendarSection, CalendarDayItemPageDto>> _fetchFirstPages({
    required DateTime date,
    required String timezone,
    required String snapshotToken,
  }) async {
    final encodedDate = CalendarDateMath.formatDate(date);
    final pages = await Future.wait([
      for (final section in CalendarSection.values)
        _gateway.listDayItems(
          CalendarListDayItemsRequestDto(
            date: encodedDate,
            timezone: timezone,
            section: section,
            snapshotToken: snapshotToken,
            pageSize: pageSize,
          ),
        ),
    ]);
    return {
      for (var index = 0; index < CalendarSection.values.length; index++)
        CalendarSection.values[index]: pages[index],
    };
  }

  void _commitSnapshot({
    required int generation,
    required CalendarRangeSummaryResponseDto range,
    required Map<CalendarSection, CalendarDayItemPageDto> pages,
    required bool fromCache,
  }) {
    if (!_isCurrent(generation)) return;
    for (final section in CalendarSection.values) {
      final page = pages[section];
      if (page == null || page.snapshotToken != range.snapshotToken) {
        throw const FormatException(
          'Calendar snapshot pages do not share one snapshot token.',
        );
      }
    }
    _setState(
      _state.copyWith(
        rangePhase: CalendarRangePhase.ready,
        rangeDays: range.days,
        snapshotToken: range.snapshotToken,
        eventSection: _readySection(pages[CalendarSection.event]!),
        habitSection: _readySection(pages[CalendarSection.habit]!),
        anniversarySection: _readySection(pages[CalendarSection.anniversary]!),
        errorMessage: null,
        showingCachedSnapshot: fromCache,
        generation: generation,
      ),
    );
  }

  void _commitFailure(Object error, {required bool preserveSnapshot}) {
    final message = _messageFor(error);
    if (preserveSnapshot && _state.rangeDays.isNotEmpty) {
      _setState(
        _state.copyWith(
          rangePhase: CalendarRangePhase.error,
          eventSection: _state.eventSection.copyWith(
            phase: CalendarSectionPhase.error,
            errorMessage: message,
          ),
          habitSection: _state.habitSection.copyWith(
            phase: CalendarSectionPhase.error,
            errorMessage: message,
          ),
          anniversarySection: _state.anniversarySection.copyWith(
            phase: CalendarSectionPhase.error,
            errorMessage: message,
          ),
          errorMessage: message,
        ),
      );
      return;
    }
    _setState(
      _state.copyWith(
        rangePhase: CalendarRangePhase.error,
        rangeDays: const [],
        snapshotToken: null,
        eventSection: _errorSection(CalendarSection.event, message),
        habitSection: _errorSection(CalendarSection.habit, message),
        anniversarySection: _errorSection(CalendarSection.anniversary, message),
        errorMessage: message,
        showingCachedSnapshot: false,
      ),
    );
  }

  Map<CalendarSection, CalendarDayItemPageDto>? _cachedPages({
    required DateTime date,
    required String? snapshotToken,
  }) {
    if (snapshotToken == null) return null;
    final result = <CalendarSection, CalendarDayItemPageDto>{};
    for (final section in CalendarSection.values) {
      final page =
          _dayCache[_DayCacheKey(
            timezone: _state.timezone,
            date: CalendarDateMath.formatDate(date),
            section: section,
          )];
      if (page == null || page.snapshotToken != snapshotToken) return null;
      result[section] = page;
    }
    return result;
  }

  CalendarSectionState _sectionFromCacheOrLoading(
    CalendarSection section,
    Map<CalendarSection, CalendarDayItemPageDto>? pages,
  ) {
    final page = pages?[section];
    return page == null ? _loadingSection(section) : _readySection(page);
  }

  CalendarSectionState _readySection(CalendarDayItemPageDto page) =>
      CalendarSectionState(
        section: page.section,
        phase: CalendarSectionPhase.ready,
        items: page.items,
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );

  CalendarSectionState _loadingSection(CalendarSection section) =>
      CalendarSectionState(
        section: section,
        phase: CalendarSectionPhase.loading,
      );

  CalendarSectionState _errorSection(CalendarSection section, String message) =>
      CalendarSectionState(
        section: section,
        phase: CalendarSectionPhase.error,
        errorMessage: message,
      );

  CalendarSectionState _refreshingOrLoading(CalendarSectionState section) =>
      section.items.isEmpty
      ? _loadingSection(section.section)
      : section.copyWith(
          phase: CalendarSectionPhase.refreshing,
          errorMessage: null,
        );

  CalendarSectionState _invalidateSectionCursor(CalendarSectionState section) =>
      _refreshingOrLoading(section.copyWith(hasMore: false, nextCursor: null));

  CalendarSectionState _settleInterruptedSection(
    CalendarSectionState section,
  ) => switch (section.phase) {
    CalendarSectionPhase.loadingMore || CalendarSectionPhase.refreshing =>
      section.copyWith(phase: CalendarSectionPhase.ready, errorMessage: null),
    CalendarSectionPhase.loading when section.items.isNotEmpty =>
      section.copyWith(phase: CalendarSectionPhase.ready, errorMessage: null),
    _ => section,
  };

  String _messageFor(Object error) {
    if (error is CalendarGatewayFailure) {
      return switch (error.code) {
        'CALENDAR_SNAPSHOT_EXPIRED' => '日历数据已更新，正在重新载入',
        'TIMEZONE_ID_INVALID' => '设备时区不可用，请检查系统时间设置',
        'STORAGE_IO_ERROR' || 'STORAGE_DATA_CORRUPTED' => '本地日历暂时无法读取，请稍后重试',
        'CONTRACT_VALIDATION_FAILED' ||
        'CONTRACT_VERSION_UNSUPPORTED' ||
        'CALENDAR_SNAPSHOT_INVALID' ||
        'CALENDAR_CURSOR_INVALID' ||
        'CALENDAR_CURSOR_QUERY_MISMATCH' => '日历数据协议异常，请更新应用或重试',
        _ => error.retryable ? '日历加载失败，请重试' : error.message,
      };
    }
    if (error is FormatException) return '日历数据协议异常，请更新应用或重试';
    return '日历加载失败，请稍后重试';
  }

  void _invalidateCaches() {
    _rangeCache.clear();
    _dayCache.clear();
    _loadMoreInFlight.clear();
  }

  int _nextGeneration() {
    _generation += 1;
    return _generation;
  }

  bool get _canInteract =>
      !_disposed && _initialized && _active && _state.timezone.isNotEmpty;

  bool _isCurrent(int generation) =>
      !_disposed && _active && generation == _generation;

  void _setState(CalendarState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _loadMoreInFlight.clear();
    super.dispose();
  }
}

class _RangeCacheKey {
  const _RangeCacheKey({
    required this.timezone,
    required this.start,
    required this.end,
  });

  factory _RangeCacheKey.fromRequest(CalendarRangeSummaryRequestDto request) =>
      _RangeCacheKey(
        timezone: request.timezone,
        start: request.rangeStartDate,
        end: request.rangeEndDate,
      );

  final String timezone;
  final String start;
  final String end;

  @override
  bool operator ==(Object other) =>
      other is _RangeCacheKey &&
      other.timezone == timezone &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(timezone, start, end);
}

class _DayCacheKey {
  const _DayCacheKey({
    required this.timezone,
    required this.date,
    required this.section,
  });

  final String timezone;
  final String date;
  final CalendarSection section;

  @override
  bool operator ==(Object other) =>
      other is _DayCacheKey &&
      other.timezone == timezone &&
      other.date == date &&
      other.section == section;

  @override
  int get hashCode => Object.hash(timezone, date, section);
}

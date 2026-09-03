import '../../native_contract/calendar/calendar_contract_enums.dart';
import '../../native_contract/calendar/calendar_response_dtos.dart';
import 'calendar_date_math.dart';

enum CalendarRangePhase { initial, loading, ready, refreshing, error }

enum CalendarSectionPhase {
  initial,
  loading,
  ready,
  refreshing,
  error,
  loadingMore,
}

class CalendarSectionState {
  const CalendarSectionState({
    required this.section,
    this.phase = CalendarSectionPhase.initial,
    this.items = const [],
    this.hasMore = false,
    this.nextCursor,
    this.errorMessage,
  });

  final CalendarSection section;
  final CalendarSectionPhase phase;
  final List<CalendarDayItemDto> items;
  final bool hasMore;
  final String? nextCursor;
  final String? errorMessage;

  bool get isBusy =>
      phase == CalendarSectionPhase.loading ||
      phase == CalendarSectionPhase.refreshing ||
      phase == CalendarSectionPhase.loadingMore;

  CalendarSectionState copyWith({
    CalendarSectionPhase? phase,
    List<CalendarDayItemDto>? items,
    bool? hasMore,
    Object? nextCursor = _unset,
    Object? errorMessage = _unset,
  }) => CalendarSectionState(
    section: section,
    phase: phase ?? this.phase,
    items: items == null ? this.items : List.unmodifiable(items),
    hasMore: hasMore ?? this.hasMore,
    nextCursor: identical(nextCursor, _unset)
        ? this.nextCursor
        : nextCursor as String?,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

class CalendarState {
  CalendarState({
    required this.selectedDate,
    required this.anchorDate,
    required this.visibleRangeStart,
    required this.visibleRangeEnd,
    required this.viewMode,
    required this.isCollapsed,
    required this.today,
    required this.timezone,
    required this.rangePhase,
    required List<CalendarRangeDaySummaryDto> rangeDays,
    required this.eventSection,
    required this.habitSection,
    required this.anniversarySection,
    required this.generation,
    this.snapshotToken,
    this.errorMessage,
    this.showingCachedSnapshot = false,
  }) : rangeDays = List.unmodifiable(rangeDays);

  factory CalendarState.initial(DateTime today) {
    final date = CalendarDateMath.dateOnly(today);
    final range = CalendarDateMath.visibleRange(date, CalendarViewMode.week);
    return CalendarState(
      selectedDate: date,
      anchorDate: date,
      visibleRangeStart: range.start,
      visibleRangeEnd: range.end,
      viewMode: CalendarViewMode.week,
      isCollapsed: true,
      today: date,
      timezone: '',
      rangePhase: CalendarRangePhase.initial,
      rangeDays: const [],
      eventSection: const CalendarSectionState(section: CalendarSection.event),
      habitSection: const CalendarSectionState(section: CalendarSection.habit),
      anniversarySection: const CalendarSectionState(
        section: CalendarSection.anniversary,
      ),
      generation: 0,
    );
  }

  final DateTime selectedDate;
  final DateTime anchorDate;
  final DateTime visibleRangeStart;
  final DateTime visibleRangeEnd;
  final CalendarViewMode viewMode;
  final bool isCollapsed;
  final DateTime today;
  final String timezone;
  final CalendarRangePhase rangePhase;
  final List<CalendarRangeDaySummaryDto> rangeDays;
  final String? snapshotToken;
  final CalendarSectionState eventSection;
  final CalendarSectionState habitSection;
  final CalendarSectionState anniversarySection;
  final String? errorMessage;
  final bool showingCachedSnapshot;
  final int generation;

  CalendarDateRange get visibleRange =>
      CalendarDateRange(start: visibleRangeStart, end: visibleRangeEnd);

  bool get hasCompleteSnapshot =>
      snapshotToken != null &&
      rangeDays.isNotEmpty &&
      eventSection.phase != CalendarSectionPhase.initial &&
      eventSection.phase != CalendarSectionPhase.loading &&
      habitSection.phase != CalendarSectionPhase.initial &&
      habitSection.phase != CalendarSectionPhase.loading &&
      anniversarySection.phase != CalendarSectionPhase.initial &&
      anniversarySection.phase != CalendarSectionPhase.loading;

  bool get allSectionsEmpty =>
      eventSection.items.isEmpty &&
      habitSection.items.isEmpty &&
      anniversarySection.items.isEmpty;

  CalendarSectionState section(CalendarSection section) => switch (section) {
    CalendarSection.event => eventSection,
    CalendarSection.habit => habitSection,
    CalendarSection.anniversary => anniversarySection,
  };

  CalendarState copyWith({
    DateTime? selectedDate,
    DateTime? anchorDate,
    DateTime? visibleRangeStart,
    DateTime? visibleRangeEnd,
    CalendarViewMode? viewMode,
    bool? isCollapsed,
    DateTime? today,
    String? timezone,
    CalendarRangePhase? rangePhase,
    List<CalendarRangeDaySummaryDto>? rangeDays,
    Object? snapshotToken = _unset,
    CalendarSectionState? eventSection,
    CalendarSectionState? habitSection,
    CalendarSectionState? anniversarySection,
    Object? errorMessage = _unset,
    bool? showingCachedSnapshot,
    int? generation,
  }) => CalendarState(
    selectedDate: selectedDate ?? this.selectedDate,
    anchorDate: anchorDate ?? this.anchorDate,
    visibleRangeStart: visibleRangeStart ?? this.visibleRangeStart,
    visibleRangeEnd: visibleRangeEnd ?? this.visibleRangeEnd,
    viewMode: viewMode ?? this.viewMode,
    isCollapsed: isCollapsed ?? this.isCollapsed,
    today: today ?? this.today,
    timezone: timezone ?? this.timezone,
    rangePhase: rangePhase ?? this.rangePhase,
    rangeDays: rangeDays ?? this.rangeDays,
    snapshotToken: identical(snapshotToken, _unset)
        ? this.snapshotToken
        : snapshotToken as String?,
    eventSection: eventSection ?? this.eventSection,
    habitSection: habitSection ?? this.habitSection,
    anniversarySection: anniversarySection ?? this.anniversarySection,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
    showingCachedSnapshot: showingCachedSnapshot ?? this.showingCachedSnapshot,
    generation: generation ?? this.generation,
  );

  CalendarState withSection(CalendarSectionState value) =>
      switch (value.section) {
        CalendarSection.event => copyWith(eventSection: value),
        CalendarSection.habit => copyWith(habitSection: value),
        CalendarSection.anniversary => copyWith(anniversarySection: value),
      };
}

const Object _unset = Object();

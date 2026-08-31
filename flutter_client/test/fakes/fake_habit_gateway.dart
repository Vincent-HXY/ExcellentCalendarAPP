import 'package:excellent_calendar/gateway_interfaces/habit_gateway.dart';
import 'package:excellent_calendar/native_contract/common/pagination_response_dto.dart';
import 'package:excellent_calendar/native_contract/habit/habit_contract_enums.dart';
import 'package:excellent_calendar/native_contract/habit/habit_request_dtos.dart';
import 'package:excellent_calendar/native_contract/habit/habit_response_dtos.dart';

/// Scripted development projection derived from contracts/fixtures/habit.
///
/// Mutations only select prepared snapshots. This fake intentionally does not
/// derive lifecycle, statistics, remaining days, reminder identity or order.
class FakeHabitGateway implements HabitGateway {
  FakeHabitGateway({this.delay = const Duration(milliseconds: 180)})
    : _items = List.of(_seedSummaries()),
      _todayProgress = _initialProgress;

  final Duration delay;
  final List<HabitSummaryResponseDto> _items;
  HabitTodayProgressResponseDto _todayProgress;
  final Set<String> _deleted = {};
  Object? nextFailure;

  @override
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request) async {
    await _wait();
    final created = _summary(
      _id(8),
      HabitLifecycleStatusContract.active,
      HabitDailyStatusContract.absent,
      title: request.title,
      quantitative: request.targetCountHundredths != null,
    );
    _replaceOrAdd(created);
    final detail = _detailFor(created);
    return HabitMutationResponseDto(detail: detail, capability: _capability());
  }

  @override
  Future<HabitMutationResponseDto> update(UpdateHabitRequestDto request) async {
    await _wait();
    final current = _summaryById(request.id);
    _replace(
      request.id,
      _summary(
        request.id,
        current.lifecycleStatus,
        current.today?.status,
        title: request.title,
        quantitative: request.targetCountHundredths != null,
      ),
    );
    return HabitMutationResponseDto(
      detail: _detail(request.id),
      capability: _capability(),
    );
  }

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) async {
    await _wait();
    final visible = _items
        .where((item) => !_deleted.contains(item.habit.id))
        .toList();
    return HabitListResponseDto(
      items: visible,
      pagination: PaginationResponseDto(
        total: visible.length,
        page: 1,
        pageSize: 100,
        hasMore: false,
        nextCursor: null,
      ),
      // Fixture-derived global aggregate; it is deliberately independent of
      // the returned page so pagination bugs remain observable in tests.
      todayProgress: _todayProgress,
    );
  }

  @override
  Future<HabitDetailResponseDto> detail(
    GetHabitDetailRequestDto request,
  ) async {
    await _wait();
    return _detail(request.id);
  }

  @override
  Future<HabitMutationResponseDto> end(
    HabitOptimisticRequestDto request,
  ) async {
    await _wait();
    _replace(
      request.id,
      _summary(request.id, HabitLifecycleStatusContract.endedEarly, null),
    );
    return HabitMutationResponseDto(
      detail: _detail(request.id),
      capability: _capability(),
    );
  }

  @override
  Future<HabitDeleteOperationResponseDto> delete(
    HabitOptimisticRequestDto request,
  ) async {
    await _wait();
    _deleted.add(request.id);
    return HabitDeleteOperationResponseDto(
      habitId: request.id,
      deletedAt: DateTime.utc(2026, 8, 28, 12),
      capability: _capability(),
    );
  }

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) async {
    await _wait();
    final current = _summaryById(request.habitId);
    final status = request.status == HabitCheckInStatusContract.skipped
        ? HabitDailyStatusContract.skipped
        : request.status == HabitCheckInStatusContract.partial
        ? HabitDailyStatusContract.partial
        : HabitDailyStatusContract.done;
    final replacement = _summary(
      request.habitId,
      current.lifecycleStatus,
      status,
    );
    _replace(request.habitId, replacement);
    _todayProgress = status == HabitDailyStatusContract.done
        ? _afterDoneProgress
        : _initialProgress;
    return _checkInMutation(replacement.today);
  }

  @override
  Future<HabitCheckInMutationResponseDto> clearCheckIn(
    ClearHabitCheckInRequestDto request,
  ) async {
    await _wait();
    final current = _summaryById(request.habitId);
    final replacement = _summary(
      request.habitId,
      current.lifecycleStatus,
      HabitDailyStatusContract.absent,
    );
    _replace(request.habitId, replacement);
    _todayProgress = _initialProgress;
    return _checkInMutation(replacement.today);
  }

  @override
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  ) async {
    await _wait();
    final start = DateTime.parse(request.startDate);
    final end = DateTime.parse(request.endDate);
    final items = <HabitDailyStatusResponseDto>[];
    for (
      var day = start;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      items.add(
        _daily(
          _date(day),
          HabitDailyStatusContract.missed,
          quantitative: false,
        ),
      );
    }
    return HabitDailyStatusListResponseDto(
      habitId: request.habitId,
      startDate: request.startDate,
      endDate: request.endDate,
      items: items,
    );
  }

  @override
  Future<HabitMutationResponseDto> setReminder(
    SetHabitReminderRequestDto request,
  ) async {
    await _wait();
    return HabitMutationResponseDto(
      detail: _detail(request.habitId),
      capability: _capability(),
    );
  }

  Future<void> _wait() async {
    await Future<void>.delayed(delay);
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
  }

  HabitSummaryResponseDto _summaryById(String id) => _items.firstWhere(
    (item) => item.habit.id == id,
    orElse: () => throw const HabitGatewayFailure(
      code: 'HABIT_NOT_FOUND',
      message: 'Habit not found',
      retryable: false,
    ),
  );

  HabitDetailResponseDto _detail(String id) {
    if (_deleted.contains(id)) {
      throw const HabitGatewayFailure(
        code: 'HABIT_TARGET_DELETED',
        message: 'Habit target is deleted',
        retryable: false,
      );
    }
    return _detailFor(_summaryById(id));
  }

  void _replace(String id, HabitSummaryResponseDto value) {
    final index = _items.indexWhere((item) => item.habit.id == id);
    if (index < 0) {
      throw const HabitGatewayFailure(
        code: 'HABIT_NOT_FOUND',
        message: 'Habit not found',
        retryable: false,
      );
    }
    _items[index] = value;
  }

  void _replaceOrAdd(HabitSummaryResponseDto value) {
    final index = _items.indexWhere((item) => item.habit.id == value.habit.id);
    if (index < 0) {
      _items.add(value);
    } else {
      _items[index] = value;
    }
  }
}

const _initialProgress = HabitTodayProgressResponseDto(
  asOfDate: '2026-08-28',
  activeCount: 4,
  doneCount: 1,
  eligibleCount: 3,
  skippedCount: 1,
  partialCount: 1,
  absentCount: 1,
);

const _afterDoneProgress = HabitTodayProgressResponseDto(
  asOfDate: '2026-08-28',
  activeCount: 4,
  doneCount: 2,
  eligibleCount: 3,
  skippedCount: 1,
  partialCount: 1,
  absentCount: 0,
);

List<HabitSummaryResponseDto> _seedSummaries() => [
  _summary(
    _id(1),
    HabitLifecycleStatusContract.active,
    HabitDailyStatusContract.absent,
    title: '晨间阅读 📚',
  ),
  _summary(
    _id(2),
    HabitLifecycleStatusContract.active,
    HabitDailyStatusContract.partial,
    title: '喝水',
    quantitative: true,
  ),
  _summary(
    _id(3),
    HabitLifecycleStatusContract.active,
    HabitDailyStatusContract.done,
    title: '散步',
  ),
  _summary(
    _id(4),
    HabitLifecycleStatusContract.active,
    HabitDailyStatusContract.skipped,
    title: '冥想',
  ),
  _summary(_id(5), HabitLifecycleStatusContract.upcoming, null, title: '九月早起'),
  _summary(
    _id(6),
    HabitLifecycleStatusContract.completed,
    null,
    title: '21 天拉伸',
  ),
  _summary(
    _id(7),
    HabitLifecycleStatusContract.endedEarly,
    null,
    title: '写作挑战',
  ),
];

HabitSummaryResponseDto _summary(
  String id,
  HabitLifecycleStatusContract lifecycle,
  HabitDailyStatusContract? status, {
  String? title,
  bool? quantitative,
}) {
  final existing = _seedTitle(id);
  final isQuantity = quantitative ?? id == _id(2);
  final habit = HabitResponseDto(
    id: id,
    title: title ?? existing,
    description: '由 Habit Contract fixture 派生的预览快照',
    categoryId: null,
    recurrenceId: _recurrenceId(id),
    targetCountHundredths: isQuantity ? 800 : null,
    unit: isQuantity ? '杯' : null,
    startDate: lifecycle == HabitLifecycleStatusContract.upcoming
        ? '2026-09-01'
        : '2026-08-01',
    endDate: '2026-09-20',
    endedDate: lifecycle == HabitLifecycleStatusContract.endedEarly
        ? '2026-08-28'
        : null,
    isActive: lifecycle != HabitLifecycleStatusContract.endedEarly,
    createdAt: DateTime.utc(2026, 8, 1, 8),
    updatedAt: DateTime.utc(2026, 8, 28, 8),
    deletedAt: null,
  );
  return HabitSummaryResponseDto(
    habit: habit,
    lifecycleStatus: lifecycle,
    today: status == null
        ? null
        : _daily('2026-08-28', status, quantitative: isQuantity),
    statistics: _statistics(quantitative: isQuantity),
    reminderSettings: _reminderSettings(id),
    challengeTimeProgress: lifecycle == HabitLifecycleStatusContract.upcoming
        ? 0
        : lifecycle == HabitLifecycleStatusContract.completed
        ? 1
        : lifecycle == HabitLifecycleStatusContract.endedEarly
        ? 0.47
        : 0.55,
    remainingDays: lifecycle == HabitLifecycleStatusContract.upcoming
        ? 20
        : lifecycle == HabitLifecycleStatusContract.active
        ? 24
        : 0,
  );
}

HabitDetailResponseDto _detailFor(HabitSummaryResponseDto summary) {
  final upcoming =
      summary.lifecycleStatus == HabitLifecycleStatusContract.upcoming;
  final history = upcoming
      ? <HabitDailyStatusResponseDto>[]
      : <HabitDailyStatusResponseDto>[
          if (summary.today != null) summary.today!,
          _daily(
            '2026-08-27',
            HabitDailyStatusContract.done,
            quantitative: summary.habit.isQuantitative,
          ),
          _daily(
            '2026-08-26',
            HabitDailyStatusContract.skipped,
            quantitative: summary.habit.isQuantitative,
          ),
          _daily(
            '2026-08-25',
            HabitDailyStatusContract.missed,
            quantitative: summary.habit.isQuantitative,
          ),
        ];
  return HabitDetailResponseDto(
    habit: summary.habit,
    recurrence: HabitRecurrenceResponseDto(
      id: summary.habit.recurrenceId,
      createdAt: DateTime.utc(2026, 8, 1, 8),
      updatedAt: DateTime.utc(2026, 8, 1, 8),
    ),
    lifecycleStatus: summary.lifecycleStatus,
    statistics: summary.statistics,
    reminderSettings: summary.reminderSettings,
    today: summary.today,
    history: history,
    historyStartDate: history.isEmpty ? null : history.last.date,
    historyEndDate: history.isEmpty ? null : history.first.date,
    hasEarlierHistory: history.isNotEmpty,
    hasEverCheckedIn: !upcoming,
    latestCheckInDate: upcoming ? null : '2026-08-27',
    challengeTimeProgress: summary.challengeTimeProgress,
    remainingDays: summary.remainingDays,
  );
}

HabitDailyStatusResponseDto _daily(
  String date,
  HabitDailyStatusContract status, {
  required bool quantitative,
}) {
  final checkStatus = switch (status) {
    HabitDailyStatusContract.done => HabitCheckInStatusContract.done,
    HabitDailyStatusContract.partial => HabitCheckInStatusContract.partial,
    HabitDailyStatusContract.skipped => HabitCheckInStatusContract.skipped,
    _ => null,
  };
  final checkIn = checkStatus == null
      ? null
      : HabitCheckInResponseDto(
          id: _checkInId(date, status.index),
          habitId: quantitative ? _id(2) : _id(1),
          checkDate: date,
          status: checkStatus,
          completedCountHundredths:
              checkStatus == HabitCheckInStatusContract.skipped
              ? null
              : quantitative
              ? checkStatus == HabitCheckInStatusContract.partial
                    ? 300
                    : 800
              : null,
          targetCountSnapshotHundredths:
              checkStatus == HabitCheckInStatusContract.skipped || !quantitative
              ? null
              : 800,
          unitSnapshot:
              checkStatus == HabitCheckInStatusContract.skipped || !quantitative
              ? null
              : '杯',
          completedAt: checkStatus == HabitCheckInStatusContract.skipped
              ? null
              : DateTime.utc(2026, 8, 28, 8),
          note: null,
          source: HabitCheckInSourceContract.manual,
          createdAt: DateTime.utc(2026, 8, 28, 8),
          updatedAt: DateTime.utc(2026, 8, 28, 8),
        );
  return HabitDailyStatusResponseDto(
    date: date,
    status: status,
    isFinal:
        status == HabitDailyStatusContract.done ||
        status == HabitDailyStatusContract.skipped ||
        status == HabitDailyStatusContract.missed,
    checkIn: checkIn,
    completionRatio: status == HabitDailyStatusContract.done
        ? 1
        : status == HabitDailyStatusContract.partial
        ? 0.375
        : null,
  );
}

HabitStatisticsResponseDto _statistics({required bool quantitative}) =>
    HabitStatisticsResponseDto(
      asOfDate: '2026-08-28',
      elapsedEligibleDays: 24,
      doneDays: 18,
      skippedDays: 2,
      partialDays: quantitative ? 1 : 0,
      missedDays: quantitative ? 3 : 4,
      currentStreak: 5,
      longestStreak: 8,
      completionRate7Days: 0.8,
      completionRate30Days: 0.75,
      completionRateAll: 0.75,
      quantityProgressRate7Days: quantitative ? 0.72 : null,
      quantityProgressRate30Days: quantitative ? 0.68 : null,
      quantityProgressRateAll: quantitative ? 0.68 : null,
      totalCompletedCountHundredths: quantitative ? 12800 : null,
      averageCompletedCountPerEligibleDayHundredths: quantitative ? 582 : null,
    );

HabitReminderSettingsResponseDto _reminderSettings(String id) =>
    HabitReminderSettingsResponseDto(
      isEnabled: true,
      template: HabitReminderTemplateResponseDto(
        templateKey: _templateId(id),
        habitId: id,
        localTime: '09:00',
        isEnabled: true,
        createdAt: DateTime.utc(2026, 8, 1, 8),
        updatedAt: DateTime.utc(2026, 8, 1, 8),
        deletedAt: null,
      ),
      activeReminderCount: 1,
      scheduleReconciliationRequired: false,
    );

HabitScheduleCapabilityResponseDto _capability() =>
    HabitScheduleCapabilityResponseDto(
      scheduleStatus: HabitScheduleStatusContract.scheduledExact,
      scheduleReconciliationRequired: false,
      notificationPermissionStatus: HabitNotificationPermissionContract.granted,
      exactAlarmPermissionStatus: HabitExactAlarmPermissionContract.granted,
      degradationReasons: const [],
    );

HabitCheckInMutationResponseDto _checkInMutation(
  HabitDailyStatusResponseDto? daily,
) => HabitCheckInMutationResponseDto(
  checkIn: daily?.checkIn,
  dailyStatus:
      daily ??
      _daily(
        '2026-08-28',
        HabitDailyStatusContract.absent,
        quantitative: false,
      ),
  statistics: _statistics(
    quantitative: daily?.checkIn?.completedCountHundredths != null,
  ),
  reminderSettings: _reminderSettings(daily?.checkIn?.habitId ?? _id(1)),
  capability: _capability(),
  idempotentReplay: false,
);

String _seedTitle(String id) => switch (id) {
  final value when value == _id(1) => '晨间阅读 📚',
  final value when value == _id(2) => '喝水',
  final value when value == _id(3) => '散步',
  final value when value == _id(4) => '冥想',
  final value when value == _id(5) => '九月早起',
  final value when value == _id(6) => '21 天拉伸',
  final value when value == _id(7) => '写作挑战',
  _ => '新习惯',
};
String _id(int value) =>
    '${value.toString().padLeft(8, '0')}-1111-4111-8111-111111111111';
String _recurrenceId(String id) =>
    '${id.substring(0, 8)}-2222-4222-8222-222222222222';
String _templateId(String id) =>
    '${id.substring(0, 8)}-3333-4333-8333-333333333333';
String _checkInId(String date, int suffix) =>
    '44444444-4444-4444-8444-${date.replaceAll('-', '').padRight(11, '0')}$suffix';
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

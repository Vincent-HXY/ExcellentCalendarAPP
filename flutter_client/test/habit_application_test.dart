import 'dart:async';

import 'package:excellent_calendar/application/habit/habit_detail_controller.dart';
import 'package:excellent_calendar/application/habit/habit_day_controller.dart';
import 'package:excellent_calendar/application/habit/habit_form_controller.dart';
import 'package:excellent_calendar/application/habit/habit_list_controller.dart';
import 'package:excellent_calendar/native_contract/common/pagination_response_dto.dart';
import 'package:excellent_calendar/native_contract/habit/habit_request_dtos.dart';
import 'package:excellent_calendar/native_contract/habit/habit_contract_enums.dart';
import 'package:excellent_calendar/native_contract/habit/habit_response_dtos.dart';
import 'package:excellent_calendar/native_contract/shared/civil_date.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_habit_gateway.dart';

void main() {
  test('decimal parser preserves exact neighbouring safe integers', () {
    expect(parseHundredths('90071992547409.90'), 9007199254740990);
    expect(parseHundredths('90071992547409.91'), 9007199254740991);
    expect(() => parseHundredths('90071992547409.92'), throwsFormatException);
    expect(() => parseHundredths('1.001'), throwsFormatException);
    expect(parseHundredths('0'), 0);
  });

  test(
    'civil-date arithmetic is timezone-independent across DST boundaries',
    () {
      expect(CivilDate(2026, 3, 7).addDays(1).format(), '2026-03-08');
      expect(CivilDate(2026, 3, 8).addDays(1).format(), '2026-03-09');
      expect(CivilDate(2026, 11, 1).addDays(1).format(), '2026-11-02');
      expect(CivilDate(2026, 3, 29).addDays(1).format(), '2026-03-30');
      expect(CivilDate(2026, 10, 25).addDays(1).format(), '2026-10-26');
      expect(CivilDate(2024, 2, 29).addYearsClamped(1).format(), '2025-02-28');
      expect(CivilDate(2026, 1, 31).addMonthsClamped(1).format(), '2026-02-28');
      expect(
        CivilDate(2026, 3, 10).addDays(-1).addDays(-29).format(),
        '2026-02-08',
      );
      expect(
        CivilDate(2026, 1, 1).inclusiveDaysUntil(CivilDate(2027, 2, 4)),
        400,
      );
    },
  );

  test(
    'duration presets clamp month end and leap year without exceeding 400',
    () {
      final controller = HabitFormController(
        gateway: FakeHabitGateway(delay: Duration.zero),
        timezoneProvider: () => 'Asia/Shanghai',
        initialStartDate: DateTime(2024, 2, 29),
      );
      controller.applyPreset(HabitDurationPreset.year1);
      expect(controller.endDate, DateTime(2025, 2, 27));
      expect(controller.plannedDays, 365);

      controller.setStartDate(DateTime(2026, 1, 31));
      controller.applyPreset(HabitDurationPreset.month1);
      expect(controller.endDate, DateTime(2026, 2, 27));
      controller.dispose();
    },
  );

  test(
    'new habit defaults to 30 inclusive days and submits that range',
    () async {
      final gateway = _RecordingCreateGateway();
      final controller = HabitFormController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
        initialStartDate: DateTime(2026, 8, 28),
      );

      expect(controller.startDate, DateTime(2026, 8, 28));
      expect(controller.endDate, DateTime(2026, 9, 26));
      expect(controller.plannedDays, 30);

      controller.setTitle('默认三十天');
      expect(await controller.submit(), isNotNull);
      expect(gateway.lastCreate?.startDate, '2026-08-28');
      expect(gateway.lastCreate?.endDate, '2026-09-26');
      controller.dispose();
    },
  );

  test(
    'duplicate submit is ignored and emoji counts as one code point',
    () async {
      final controller = HabitFormController(
        gateway: FakeHabitGateway(delay: const Duration(milliseconds: 20)),
        timezoneProvider: () => 'Asia/Shanghai',
        initialStartDate: DateTime(2026, 8, 28),
      );
      controller.setTitle('${List.filled(79, 'a').join()}📚');
      final first = controller.submit();
      final second = controller.submit();
      expect(await second, isNull);
      expect(await first, isNotNull);
      controller.dispose();
    },
  );

  test(
    'latest list request wins and stale failure cannot replace ready data',
    () async {
      final gateway = _QueuedListGateway();
      final controller = HabitListController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );
      final first = controller.load();
      final second = controller.load();
      final response = await FakeHabitGateway(
        delay: Duration.zero,
      ).list(const ListHabitsRequestDto(timezone: 'Asia/Shanghai'));
      gateway.completers[1].complete(response);
      await second;
      gateway.completers[0].completeError(StateError('stale'));
      await first;

      expect(controller.phase, HabitListPhase.ready);
      expect(controller.items, isNotEmpty);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    },
  );

  test(
    'habit list follows cursor pages, deduplicates ids, and keeps first-page today progress',
    () async {
      final gateway = _PagedListGateway();
      final controller = HabitListController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );

      await controller.load();
      final firstPageProgress = controller.todayProgress;
      expect(controller.items, hasLength(100));
      expect(controller.hasMore, isTrue);

      await controller.loadMore();

      expect(controller.items, hasLength(101));
      expect(controller.items.map((item) => item.id).toSet(), hasLength(101));
      expect(
        controller.items
            .singleWhere((item) => item.id == _pagedHabitId(99))
            .title,
        '第 100 个习惯（已更新）',
      );
      expect(controller.todayProgress, same(firstPageProgress));
      expect(controller.hasMore, isFalse);
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.last.pagination.cursor, _PagedListGateway.cursor);
      expect(gateway.requests.last.pagination.page, isNull);
      controller.dispose();
    },
  );

  test('per-item mutation lock blocks duplicate quick actions', () async {
    final gateway = FakeHabitGateway(delay: const Duration(milliseconds: 20));
    final controller = HabitListController(
      gateway: gateway,
      timezoneProvider: () => 'Asia/Shanghai',
      successFeedbackDelay: Duration.zero,
    );
    await controller.load();
    final item = controller.items.first;
    final first = controller.quickCheckIn(item);
    final second = controller.quickCheckIn(item);
    expect(await second, isFalse);
    expect(await first, isTrue);
    controller.dispose();
  });

  test(
    'failed quick action keeps projection and can retry explicitly',
    () async {
      final gateway = FakeHabitGateway(delay: Duration.zero);
      final controller = HabitListController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
        successFeedbackDelay: Duration.zero,
      );
      await controller.load();
      final item = controller.items.first;
      final originalStatus = item.todayStatus;
      gateway.nextFailure = StateError('transient');

      expect(await controller.quickCheckIn(item), isFalse);
      expect(controller.items.first.todayStatus, originalStatus);
      expect(controller.errorMessage, isNotNull);
      expect(controller.canRetryMutation, isTrue);

      expect(await controller.retryLastMutation(), isTrue);
      expect(controller.canRetryMutation, isFalse);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    },
  );

  test(
    'done quantitative quick action adds one and preserves note without clear',
    () async {
      final gateway = _RecordingMutationGateway();
      final controller = HabitListController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
        successFeedbackDelay: Duration.zero,
      );
      await controller.load();
      final item = controller.items.firstWhere(
        (item) => item.id == '00000002-1111-4111-8111-111111111111',
      );

      expect(item.todayStatus, HabitDailyStatusContract.done);
      expect(item.todayNote, '需要保留');
      expect(await controller.quickCheckIn(item), isTrue);
      expect(gateway.clearRequests, isEmpty);
      expect(gateway.checkInRequests.single.completedCountHundredths, 900);
      expect(gateway.checkInRequests.single.note, '需要保留');
      expect(controller.todayProgress?.asOfDate, '2026-08-28');
      expect(gateway.checkInRequests.single.checkDate, '2026-08-28');
      controller.dispose();
    },
  );

  test(
    'binary clear requires confirmation and read-only lifecycles never mutate',
    () async {
      final gateway = _RecordingMutationGateway();
      final controller = HabitListController(
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
        successFeedbackDelay: Duration.zero,
      );
      await controller.load();
      final binaryDone = controller.items.firstWhere(
        (item) => item.id == '00000003-1111-4111-8111-111111111111',
      );
      final upcoming = controller.items.firstWhere(
        (item) => item.lifecycle == HabitLifecycleStatusContract.upcoming,
      );
      final completed = controller.items.firstWhere(
        (item) => item.lifecycle == HabitLifecycleStatusContract.completed,
      );

      expect(binaryDone.requiresClearConfirmation, isTrue);
      expect(await controller.quickCheckIn(binaryDone), isFalse);
      expect(gateway.clearRequests, isEmpty);
      expect(
        await controller.quickCheckIn(binaryDone, clearConfirmed: true),
        isTrue,
      );
      expect(gateway.clearRequests, hasLength(1));
      expect(await controller.quickCheckIn(upcoming), isFalse);
      expect(await controller.quickCheckIn(completed), isFalse);
      expect(gateway.checkInRequests, isEmpty);
      controller.dispose();
    },
  );

  test(
    'selected day remains locked until exact-date projection is loaded',
    () async {
      final detail = await FakeHabitGateway(delay: Duration.zero).detail(
        const GetHabitDetailRequestDto(
          id: '00000002-1111-4111-8111-111111111111',
          timezone: 'Asia/Shanghai',
        ),
      );
      final selected = _dailyForDate(
        detail.history.first,
        '2026-08-10',
        note: '第二页备注',
      );
      final gateway = _SelectedDayGateway(
        detail: detail,
        selected: selected,
        holdDailyResponse: true,
      );
      final controller = HabitDayController(
        habitId: detail.habit.id,
        date: selected.date,
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );

      final loading = controller.initialize();
      await _eventLoop();
      expect(gateway.dailyRequests.single.startDate, selected.date);
      expect(gateway.dailyRequests.single.endDate, selected.date);
      expect(controller.phase, HabitDayPhase.loading);
      expect(controller.canMutate, isFalse);
      expect(
        await controller.set(
          status: HabitCheckInStatusContract.done,
          completedCountHundredths: 800,
          note: 'should not send',
        ),
        isFalse,
      );
      expect(gateway.checkInRequests, isEmpty);

      gateway.completeDaily();
      await loading;
      expect(controller.phase, HabitDayPhase.ready);
      expect(controller.canMutate, isTrue);
      expect(controller.status?.checkIn?.completedCountHundredths, 300);
      expect(controller.status?.checkIn?.note, '第二页备注');
      controller.dispose();
    },
  );

  test('future, out-of-range and ended habit days remain read-only', () async {
    final fake = FakeHabitGateway(delay: Duration.zero);
    final active = await fake.detail(
      const GetHabitDetailRequestDto(
        id: '00000002-1111-4111-8111-111111111111',
        timezone: 'Asia/Shanghai',
      ),
    );
    final future = HabitDailyStatusResponseDto(
      date: '2026-09-10',
      status: HabitDailyStatusContract.upcoming,
      isFinal: false,
      checkIn: null,
      completionRatio: null,
    );
    final outOfRange = HabitDailyStatusResponseDto(
      date: '2026-10-01',
      status: HabitDailyStatusContract.absent,
      isFinal: false,
      checkIn: null,
      completionRatio: null,
    );

    for (final selected in [future, outOfRange]) {
      final controller = HabitDayController(
        habitId: active.habit.id,
        date: selected.date,
        gateway: _SelectedDayGateway(detail: active, selected: selected),
        timezoneProvider: () => 'Asia/Shanghai',
      );
      await controller.initialize();
      expect(controller.canMutate, isFalse);
      controller.dispose();
    }

    for (final id in [
      '00000006-1111-4111-8111-111111111111',
      '00000007-1111-4111-8111-111111111111',
    ]) {
      final ended = await fake.detail(
        GetHabitDetailRequestDto(id: id, timezone: 'Asia/Shanghai'),
      );
      final selected = HabitDailyStatusResponseDto(
        date: '2026-08-10',
        status: HabitDailyStatusContract.missed,
        isFinal: true,
        checkIn: null,
        completionRatio: null,
      );
      final controller = HabitDayController(
        habitId: id,
        date: selected.date,
        gateway: _SelectedDayGateway(detail: ended, selected: selected),
        timezoneProvider: () => 'Asia/Shanghai',
      );
      await controller.initialize();
      expect(controller.canMutate, isFalse);
      controller.dispose();
    }
  });

  test(
    'detail mutation lock survives refresh and owns its post-commit reload',
    () async {
      final gateway = _ControlledDetailGateway();
      final controller = HabitDetailController(
        habitId: '00000001-1111-4111-8111-111111111111',
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );
      await controller.initialize();
      final reload = Completer<HabitDetailResponseDto>();
      gateway.detailResponses.add(reload);
      gateway.checkInGate = Completer<void>();

      final mutation = controller.setDay(
        date: '2026-08-28',
        status: HabitCheckInStatusContract.done,
      );
      expect(controller.isMutating, isTrue);
      await controller.load(preserve: true);
      expect(gateway.detailCalls, 1);
      expect(
        await controller.setDay(
          date: '2026-08-28',
          status: HabitCheckInStatusContract.done,
        ),
        isFalse,
      );

      gateway.checkInGate!.complete();
      await _until(() => gateway.detailCalls == 2);
      expect(controller.isMutating, isTrue);
      reload.complete(
        await FakeHabitGateway(delay: Duration.zero).detail(
          const GetHabitDetailRequestDto(
            id: '00000001-1111-4111-8111-111111111111',
            timezone: 'Asia/Shanghai',
          ),
        ),
      );
      expect(await mutation, isTrue);
      expect(controller.isMutating, isFalse);
      controller.dispose();
    },
  );

  test(
    'stale refresh cannot overwrite mutation reload and dispose is safe',
    () async {
      final gateway = _ControlledDetailGateway();
      final controller = HabitDetailController(
        habitId: '00000001-1111-4111-8111-111111111111',
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );
      await controller.initialize();
      final stale = Completer<HabitDetailResponseDto>();
      gateway.detailResponses.add(stale);
      final refresh = controller.load(preserve: true);
      await _eventLoop();
      expect(gateway.detailCalls, 2);

      expect(
        await controller.setDay(
          date: '2026-08-28',
          status: HabitCheckInStatusContract.done,
        ),
        isTrue,
      );
      final currentTitle = controller.detail!.habit.title;
      stale.complete(
        _detailWithTitle(controller.detail!.dto, 'stale response'),
      );
      await refresh;
      expect(controller.detail!.habit.title, currentTitle);

      final disposeReload = Completer<HabitDetailResponseDto>();
      gateway.detailResponses.add(disposeReload);
      final detailCallsBeforeDispose = gateway.detailCalls;
      final disposedMutation = controller.setDay(
        date: '2026-08-28',
        status: HabitCheckInStatusContract.done,
      );
      await _until(() => gateway.detailCalls == detailCallsBeforeDispose + 1);
      controller.dispose();
      disposeReload.complete(
        await FakeHabitGateway(delay: Duration.zero).detail(
          const GetHabitDetailRequestDto(
            id: '00000001-1111-4111-8111-111111111111',
            timezone: 'Asia/Shanghai',
          ),
        ),
      );
      expect(await disposedMutation, isFalse);
    },
  );

  test('form submit retains every actual scheduling capability', () async {
    const cases = {
      HabitScheduleStatusContract.scheduledExact: '提醒已按精确时间安排',
      HabitScheduleStatusContract.scheduledApproximate: '提醒将以近似时间送达',
      HabitScheduleStatusContract.pendingPermission: '数据已保存，提醒等待系统授权',
      HabitScheduleStatusContract.pendingReconciliation: '数据已保存，提醒等待系统恢复',
    };
    for (final entry in cases.entries) {
      final controller = HabitFormController(
        gateway: _CapabilityGateway(entry.key),
        timezoneProvider: () => 'Asia/Shanghai',
        initialStartDate: DateTime(2026, 8, 28),
      );
      controller.setTitle('调度状态');
      await controller.setReminderEnabled(true);
      final outcome = await controller.submit();
      expect(outcome?.capability.scheduleStatus, entry.key);
      expect(outcome?.capabilityMessage, entry.value);
      expect(controller.actualCapability, same(outcome?.capability));
      expect(controller.capabilityMessage, entry.value);
      controller.dispose();
    }
  });

  test(
    'earlier history advances by page and clamps at challenge start',
    () async {
      final gateway = _RecordingHistoryGateway();
      final controller = HabitDetailController(
        habitId: '00000001-1111-4111-8111-111111111111',
        gateway: gateway,
        timezoneProvider: () => 'Asia/Shanghai',
      );
      await controller.initialize();

      final first = await controller.loadEarlierHistory();
      expect(first?.startDate, '2026-08-01');
      expect(first?.endDate, '2026-08-24');
      expect(gateway.historyRequests, hasLength(1));

      final exhausted = await controller.loadEarlierHistory(
        beforeDate: '2026-08-01',
      );
      expect(exhausted, isNull);
      expect(gateway.historyRequests, hasLength(1));
      controller.dispose();
    },
  );
}

class _QueuedListGateway extends FakeHabitGateway {
  _QueuedListGateway() : super(delay: Duration.zero);
  final List<Completer<HabitListResponseDto>> completers = [];

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) {
    final completer = Completer<HabitListResponseDto>();
    completers.add(completer);
    return completer.future;
  }
}

class _RecordingCreateGateway extends FakeHabitGateway {
  _RecordingCreateGateway() : super(delay: Duration.zero);

  CreateHabitRequestDto? lastCreate;

  @override
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request) {
    lastCreate = request;
    return super.create(request);
  }
}

class _PagedListGateway extends FakeHabitGateway {
  _PagedListGateway() : super(delay: Duration.zero);

  static const cursor = 'habit-list-r1:page-100';
  final List<ListHabitsRequestDto> requests = [];

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) async {
    requests.add(request);
    final base = await super.list(
      const ListHabitsRequestDto(timezone: 'Asia/Shanghai'),
    );
    final source = base.items.firstWhere(
      (item) => item.lifecycleStatus == HabitLifecycleStatusContract.upcoming,
    );
    if (request.pagination.cursor == null) {
      return HabitListResponseDto(
        items: [
          for (var index = 0; index < 100; index++)
            _pagedSummary(source, index),
        ],
        pagination: const PaginationResponseDto(
          total: 101,
          page: 1,
          pageSize: 100,
          hasMore: true,
          nextCursor: cursor,
        ),
        todayProgress: base.todayProgress,
      );
    }
    return HabitListResponseDto(
      items: [
        _pagedSummary(source, 99, title: '第 100 个习惯（已更新）'),
        _pagedSummary(source, 100),
      ],
      pagination: const PaginationResponseDto(
        total: 101,
        page: 2,
        pageSize: 100,
        hasMore: false,
        nextCursor: null,
      ),
      todayProgress: const HabitTodayProgressResponseDto(
        asOfDate: '2026-08-28',
        activeCount: 0,
        doneCount: 0,
        eligibleCount: 0,
        skippedCount: 0,
        partialCount: 0,
        absentCount: 0,
      ),
    );
  }
}

HabitSummaryResponseDto _pagedSummary(
  HabitSummaryResponseDto source,
  int index, {
  String? title,
}) {
  final json = source.toJson();
  final habit = json['habit']! as Map<String, dynamic>;
  habit['id'] = _pagedHabitId(index);
  habit['title'] = title ?? '第 ${index + 1} 个习惯';
  return HabitSummaryResponseDto.fromJson(json);
}

String _pagedHabitId(int index) =>
    '${index.toRadixString(16).padLeft(8, '0')}-1111-4111-8111-111111111111';

class _RecordingHistoryGateway extends FakeHabitGateway {
  _RecordingHistoryGateway() : super(delay: Duration.zero);
  final List<ListHabitDailyStatusesRequestDto> historyRequests = [];

  @override
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  ) {
    historyRequests.add(request);
    return super.listDailyStatuses(request);
  }
}

class _RecordingMutationGateway extends FakeHabitGateway {
  _RecordingMutationGateway() : super(delay: Duration.zero);
  final List<HabitCheckInRequestDto> checkInRequests = [];
  final List<ClearHabitCheckInRequestDto> clearRequests = [];

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) async {
    final response = await super.list(request);
    final json = response.toJson();
    final items = json['items']! as List<dynamic>;
    for (final raw in items.cast<Map<String, dynamic>>()) {
      final habit = raw['habit']! as Map<String, dynamic>;
      final today = raw['today'] as Map<String, dynamic>?;
      if (habit['id'] == '00000002-1111-4111-8111-111111111111') {
        today!['status'] = 'done';
        today['is_final'] = true;
        today['completion_ratio'] = 1.0;
        final checkIn = today['check_in']! as Map<String, dynamic>;
        checkIn['status'] = 'done';
        checkIn['completed_count_hundredths'] = 800;
        checkIn['note'] = '需要保留';
      }
      if (habit['id'] == '00000003-1111-4111-8111-111111111111') {
        final checkIn = today!['check_in']! as Map<String, dynamic>;
        checkIn['note'] = '不可静默删除';
      }
    }
    return HabitListResponseDto.fromJson(json);
  }

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) {
    checkInRequests.add(request);
    return super.checkIn(request);
  }

  @override
  Future<HabitCheckInMutationResponseDto> clearCheckIn(
    ClearHabitCheckInRequestDto request,
  ) {
    clearRequests.add(request);
    return super.clearCheckIn(request);
  }
}

class _SelectedDayGateway extends FakeHabitGateway {
  _SelectedDayGateway({
    required HabitDetailResponseDto detail,
    required this.selected,
    bool holdDailyResponse = false,
  }) : detailResponse = detail,
       _dailyCompleter = holdDailyResponse
           ? Completer<HabitDailyStatusListResponseDto>()
           : null,
       super(delay: Duration.zero);

  final HabitDetailResponseDto detailResponse;
  final HabitDailyStatusResponseDto selected;
  final Completer<HabitDailyStatusListResponseDto>? _dailyCompleter;
  final List<ListHabitDailyStatusesRequestDto> dailyRequests = [];
  final List<HabitCheckInRequestDto> checkInRequests = [];

  HabitDailyStatusListResponseDto get _response =>
      HabitDailyStatusListResponseDto(
        habitId: detailResponse.habit.id,
        startDate: selected.date,
        endDate: selected.date,
        items: [selected],
      );

  void completeDaily() => _dailyCompleter!.complete(_response);

  @override
  Future<HabitDetailResponseDto> detail(
    GetHabitDetailRequestDto request,
  ) async => detailResponse;

  @override
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  ) {
    dailyRequests.add(request);
    return _dailyCompleter?.future ?? Future.value(_response);
  }

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) {
    checkInRequests.add(request);
    return super.checkIn(request);
  }
}

class _ControlledDetailGateway extends FakeHabitGateway {
  _ControlledDetailGateway() : super(delay: Duration.zero);
  final List<Completer<HabitDetailResponseDto>> detailResponses = [];
  Completer<void>? checkInGate;
  int detailCalls = 0;

  @override
  Future<HabitDetailResponseDto> detail(GetHabitDetailRequestDto request) {
    detailCalls += 1;
    if (detailResponses.isNotEmpty) {
      return detailResponses.removeAt(0).future;
    }
    return super.detail(request);
  }

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) async {
    final gate = checkInGate;
    if (gate != null) await gate.future;
    return super.checkIn(request);
  }
}

class _CapabilityGateway extends FakeHabitGateway {
  _CapabilityGateway(this.status) : super(delay: Duration.zero);
  final HabitScheduleStatusContract status;

  @override
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request) async {
    final base = await super.create(request);
    final reconciliation =
        status == HabitScheduleStatusContract.pendingPermission ||
        status == HabitScheduleStatusContract.pendingReconciliation;
    final detailJson = base.detail.toJson();
    (detailJson['reminder_settings']!
            as Map<String, dynamic>)['schedule_reconciliation_required'] =
        reconciliation;
    return HabitMutationResponseDto(
      detail: HabitDetailResponseDto.fromJson(detailJson),
      capability: HabitScheduleCapabilityResponseDto(
        scheduleStatus: status,
        scheduleReconciliationRequired: reconciliation,
        notificationPermissionStatus:
            status == HabitScheduleStatusContract.pendingPermission
            ? HabitNotificationPermissionContract.denied
            : HabitNotificationPermissionContract.granted,
        exactAlarmPermissionStatus:
            status == HabitScheduleStatusContract.scheduledApproximate
            ? HabitExactAlarmPermissionContract.denied
            : HabitExactAlarmPermissionContract.granted,
        degradationReasons: const [],
      ),
    );
  }
}

HabitDailyStatusResponseDto _dailyForDate(
  HabitDailyStatusResponseDto source,
  String date, {
  String? note,
}) {
  final json = source.toJson()..['date'] = date;
  final checkIn = json['check_in']! as Map<String, dynamic>;
  checkIn['check_date'] = date;
  checkIn['note'] = note;
  return HabitDailyStatusResponseDto.fromJson(json);
}

HabitDetailResponseDto _detailWithTitle(
  HabitDetailResponseDto source,
  String title,
) {
  final json = source.toJson();
  (json['habit']! as Map<String, dynamic>)['title'] = title;
  return HabitDetailResponseDto.fromJson(json);
}

Future<void> _eventLoop() => Future<void>.delayed(Duration.zero);

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await _eventLoop();
  }
  expect(condition(), isTrue);
}

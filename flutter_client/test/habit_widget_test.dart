import 'package:excellent_calendar/application/appearance/appearance_controller.dart';
import 'package:excellent_calendar/application/habit/habit_form_controller.dart';
import 'package:excellent_calendar/application/habit/habit_models.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/native_contract/habit/habit_contract_enums.dart';
import 'package:excellent_calendar/native_contract/habit/habit_request_dtos.dart';
import 'package:excellent_calendar/native_contract/habit/habit_response_dtos.dart';
import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';
import 'package:excellent_calendar/presentation/appearance/appearance_page.dart';
import 'package:excellent_calendar/presentation/habit/habit_design.dart';
import 'package:excellent_calendar/presentation/habit/pages/habit_day_page.dart';
import 'package:excellent_calendar/presentation/habit/pages/habit_detail_page.dart';
import 'package:excellent_calendar/presentation/habit/pages/habit_form_page.dart';
import 'package:excellent_calendar/presentation/habit/pages/habit_list_page.dart';
import 'package:excellent_calendar/presentation/habit/widgets/habit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_appearance_preferences_gateway.dart';
import 'fakes/fake_habit_gateway.dart';

void main() {
  testWidgets('Habit card ring centers the current streak instead of percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HabitCard(
            item: const HabitCardViewData(
              id: '00000001-1111-4111-8111-111111111111',
              title: '连续阅读',
              lifecycle: HabitLifecycleStatusContract.active,
              todayStatus: HabitDailyStatusContract.done,
              targetCountHundredths: null,
              completedCountHundredths: null,
              todayNote: null,
              hasTodayCheckIn: true,
              unit: null,
              challengeTimeProgress: 1,
              completionRate: 1,
              currentStreak: 5,
              remainingDays: 10,
              reminderEnabled: false,
              reminderLocalTime: null,
            ),
            mutating: false,
            succeeded: false,
            onOpen: _noop,
            onQuickAction: null,
            onExactQuantity: null,
          ),
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.text('100'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('完成率 100%，当前连续 5 天')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    'Habit card background follows completion instead of elapsed time',
    (tester) async {
      const item = HabitCardViewData(
        id: '00000001-1111-4111-8111-111111111111',
        title: '完成率与时间进度不同',
        lifecycle: HabitLifecycleStatusContract.active,
        todayStatus: HabitDailyStatusContract.partial,
        targetCountHundredths: null,
        completedCountHundredths: null,
        todayNote: null,
        hasTodayCheckIn: false,
        unit: null,
        challengeTimeProgress: 0.8,
        completionRate: 0.3,
        currentStreak: 0,
        remainingDays: 18,
        reminderEnabled: false,
        reminderLocalTime: null,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HabitCard(
              item: item,
              mutating: false,
              succeeded: false,
              onOpen: _noop,
              onQuickAction: null,
              onExactQuantity: null,
            ),
          ),
        ),
      );

      final background = tester.widget<FractionallySizedBox>(
        find.byKey(
          const ValueKey(
            'habit-completion-background-00000001-1111-4111-8111-111111111111',
          ),
        ),
      );
      expect(background.widthFactor, 0.3);
      expect(find.text('剩余 18 天'), findsOneWidget);
    },
  );

  testWidgets('quantitative card shows remaining count and target-met state', (
    tester,
  ) async {
    final cases = <({int? completed, String id, String? remaining})>[
      (
        completed: null,
        id: '00000001-1111-4111-8111-111111111111',
        remaining: '8',
      ),
      (
        completed: 300,
        id: '00000002-1111-4111-8111-111111111111',
        remaining: '5',
      ),
      (
        completed: 800,
        id: '00000003-1111-4111-8111-111111111111',
        remaining: null,
      ),
      (
        completed: 900,
        id: '00000004-1111-4111-8111-111111111111',
        remaining: null,
      ),
    ];

    for (final entry in cases) {
      final item = HabitCardViewData(
        id: entry.id,
        title: '喝水',
        lifecycle: HabitLifecycleStatusContract.active,
        todayStatus: entry.completed == null
            ? HabitDailyStatusContract.absent
            : entry.completed! < 800
            ? HabitDailyStatusContract.partial
            : HabitDailyStatusContract.done,
        targetCountHundredths: 800,
        completedCountHundredths: entry.completed,
        todayNote: null,
        hasTodayCheckIn: entry.completed != null,
        unit: '杯',
        challengeTimeProgress: 0.5,
        completionRate: 0.25,
        currentStreak: 2,
        remainingDays: 8,
        reminderEnabled: false,
        reminderLocalTime: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HabitCard(
              item: item,
              mutating: false,
              succeeded: false,
              onOpen: _noop,
              onQuickAction: _noop,
              onExactQuantity: _noop,
            ),
          ),
        ),
      );

      if (entry.remaining case final remaining?) {
        final circle = find.byKey(ValueKey('habit-remaining-${entry.id}'));
        expect(circle, findsOneWidget);
        expect(
          find.descendant(of: circle, matching: find.text(remaining)),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('habit-target-met-${entry.id}')),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(ValueKey('habit-target-met-${entry.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('habit-remaining-${entry.id}')),
          findsNothing,
        );
      }
      expect(
        find.text('${formatHundredths(entry.completed ?? 0)} / 8 杯'),
        findsOneWidget,
      );
    }
  });

  testWidgets('Habit home fits 360dp at 200% text scale in dark theme', (
    tester,
  ) async {
    _configureSmallDisplay(tester);
    final semantics = tester.ensureSemantics();
    final theme = buildHabitAppTheme(
      seedColor: const Color(0xFF0F8C91),
      brightness: Brightness.dark,
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: theme,
          home: HabitListPage(
            gateway: FakeHabitGateway(delay: Duration.zero),
            timezoneProvider: () => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日完成'), findsOneWidget);
    expect(find.text('晨间阅读 📚'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('晨间阅读')), findsWidgets);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      theme.colorScheme.surface,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('appearance update immediately changes selected local token', (
    tester,
  ) async {
    _configureSmallDisplay(tester);
    final semantics = tester.ensureSemantics();
    final controller = AppearanceController(
      FakeAppearancePreferencesGateway(delay: Duration.zero),
    );
    await controller.initialize();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: buildHabitAppTheme(
            seedColor: const Color(0xFF0F8C91),
            brightness: Brightness.dark,
          ),
          home: AppearancePage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('紫色'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('紫色'));
    await tester.pump();
    await tester.pump();

    expect(controller.token, HabitProgressColorToken.purple);
    expect(find.textContaining('保存在本机，不会同步到云端'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('紫色，已选中')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    semantics.dispose();
  });

  testWidgets('quantitative day offers +1 and exact quantity actions', (
    tester,
  ) async {
    _configureSmallDisplay(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: buildHabitAppTheme(
            seedColor: const Color(0xFF0F8C91),
            brightness: Brightness.dark,
          ),
          home: HabitDayPage(
            habitId: '00000002-1111-4111-8111-111111111111',
            date: '2026-08-28',
            gateway: FakeHabitGateway(delay: Duration.zero),
            timezoneProvider: () => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '+1 杯'), findsOneWidget);
    expect(find.text('保存数量'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '+1 杯'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('binary quick clear with note requires explicit confirmation', (
    tester,
  ) async {
    final gateway = _WidgetSafetyGateway();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: HabitListPage(
          gateway: gateway,
          timezoneProvider: () => 'Asia/Shanghai',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final clearAction = find.bySemanticsLabel('散步 撤销今日完成');
    expect(clearAction, findsOneWidget);
    await tester.tap(clearAction);
    await tester.pumpAndSettle();
    expect(find.text('撤销 散步 的今日记录？'), findsOneWidget);
    expect(gateway.clearCount, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.clearCount, 0);

    await tester.tap(clearAction);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认清除'));
    await tester.pumpAndSettle();
    expect(gateway.clearCount, 1);
    semantics.dispose();
  });

  testWidgets(
    'selected historical day hydrates quantity and note before clear',
    (tester) async {
      final base = (await tester.runAsync(
        () => FakeHabitGateway(delay: Duration.zero).detail(
          const GetHabitDetailRequestDto(
            id: '00000002-1111-4111-8111-111111111111',
            timezone: 'Asia/Shanghai',
          ),
        ),
      ))!;
      final selected = _selectedDaily(base.history.first, '2026-08-10');
      await tester.pumpWidget(
        MaterialApp(
          home: HabitDayPage(
            habitId: base.habit.id,
            date: selected.date,
            gateway: _OldDayGateway(detailResponse: base, selected: selected),
            timezoneProvider: () => 'Asia/Shanghai',
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('第二页备注'), findsOneWidget);
      await tester.tap(find.text('清除记录'));
      await tester.pump();
      expect(find.text('数量和备注会一起清除。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
    },
  );

  testWidgets('form fits dark 360dp at 200% text and keeps semantic controls', (
    tester,
  ) async {
    _configureSmallDisplay(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: buildHabitAppTheme(
            seedColor: const Color(0xFF0F8C91),
            brightness: Brightness.dark,
          ),
          home: HabitFormPage(
            gateway: FakeHabitGateway(delay: Duration.zero),
            timezoneProvider: () => 'Asia/Shanghai',
            categoryRepository: FakeCategoryRepository(),
            seed: const HabitFormSeed(
              title: '每天喝水',
              description: '',
              categoryId: null,
              quantitative: true,
              targetText: '8',
              unit: '杯',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('开始挑战'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.bySemanticsLabel(RegExp('习惯名称')), findsWidgets);
    expect(find.text('开始挑战'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('new habit form previews the default 30-day range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HabitFormPage(
          gateway: FakeHabitGateway(delay: Duration.zero),
          timezoneProvider: () => 'Asia/Shanghai',
          categoryRepository: FakeCategoryRepository(),
          initialStartDate: DateTime(2026, 8, 28),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.text(
      '最终结束日 ${formatHabitDate('2026-09-26')} · 共 30 个计划日',
    );
    await tester.scrollUntilVisible(
      preview,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text(formatHabitDate('2026-08-28')), findsOneWidget);
    expect(find.text(formatHabitDate('2026-09-26')), findsOneWidget);
    expect(preview, findsOneWidget);
  });

  testWidgets('submit shows actual pending capability before navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HabitFormPage(
          gateway: _PendingCapabilityGateway(),
          timezoneProvider: () => 'Asia/Shanghai',
          categoryRepository: FakeCategoryRepository(),
          seed: const HabitFormSeed(
            title: '按时喝水',
            description: '',
            categoryId: null,
            quantitative: false,
            targetText: '',
            unit: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('每日提醒'));
    await tester.tap(find.text('每日提醒'));
    await tester.pump();
    await tester.ensureVisible(find.text('开始挑战'));
    await tester.tap(find.text('开始挑战'));
    await tester.pumpAndSettle();

    expect(find.text('习惯已保存'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('数据已保存，提醒等待系统授权'),
      ),
      findsOneWidget,
    );
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets(
    'detail fits dark 360dp at 200% text and persists reconciliation state',
    (tester) async {
      _configureSmallDisplay(tester);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(
            theme: buildHabitAppTheme(
              seedColor: const Color(0xFF0F8C91),
              brightness: Brightness.dark,
            ),
            home: HabitDetailPage(
              habitId: '00000001-1111-4111-8111-111111111111',
              gateway: _ReconciliationDetailGateway(),
              timezoneProvider: () => 'Asia/Shanghai',
              categoryRepository: FakeCategoryRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('提醒等待系统恢复'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('挑战时间进度')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('detail keeps notification occurrence internal', (tester) async {
    const occurrenceKey = '11111111-2222-4333-8444-555555555555';
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailPage(
          habitId: '00000001-1111-4111-8111-111111111111',
          gateway: FakeHabitGateway(delay: Duration.zero),
          timezoneProvider: () => 'Asia/Shanghai',
          categoryRepository: FakeCategoryRepository(),
          focusOccurrenceKey: occurrenceKey,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(occurrenceKey), findsNothing);
    expect(find.textContaining('通知 occurrence'), findsNothing);
    expect(find.text('晨间阅读 📚'), findsOneWidget);
  });

  testWidgets('detail exposes skip today and delete in the app bar', (
    tester,
  ) async {
    final gateway = _DetailActionGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: HabitDetailPage(
          habitId: '00000001-1111-4111-8111-111111111111',
          gateway: gateway,
          timezoneProvider: () => 'Asia/Shanghai',
          categoryRepository: FakeCategoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('删除习惯'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '删除习惯'), findsNothing);
    final skipButton = find.widgetWithText(OutlinedButton, '跳过今天');
    await tester.scrollUntilVisible(
      skipButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    await tester.tap(skipButton);
    await tester.pumpAndSettle();

    expect(gateway.lastCheckIn?.status, HabitCheckInStatusContract.skipped);
    expect(gateway.lastCheckIn?.checkDate, '2026-08-28');
    expect(find.text('今天已跳过'), findsWidgets);

    await tester.tap(find.byTooltip('删除习惯'));
    await tester.pump();
    expect(find.text('删除习惯？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });
}

void _noop() {}

void _configureSmallDisplay(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _WidgetSafetyGateway extends FakeHabitGateway {
  _WidgetSafetyGateway() : super(delay: Duration.zero);
  int clearCount = 0;

  @override
  Future<HabitListResponseDto> list(ListHabitsRequestDto request) async {
    final json = (await super.list(request)).toJson();
    for (final item
        in (json['items']! as List<dynamic>).cast<Map<String, dynamic>>()) {
      final habit = item['habit']! as Map<String, dynamic>;
      if (habit['id'] == '00000003-1111-4111-8111-111111111111') {
        final today = item['today']! as Map<String, dynamic>;
        final checkIn = today['check_in']! as Map<String, dynamic>;
        checkIn['note'] = '重要备注';
      }
    }
    return HabitListResponseDto.fromJson(json);
  }

  @override
  Future<HabitCheckInMutationResponseDto> clearCheckIn(
    ClearHabitCheckInRequestDto request,
  ) {
    clearCount += 1;
    return super.clearCheckIn(request);
  }
}

class _DetailActionGateway extends FakeHabitGateway {
  _DetailActionGateway() : super(delay: Duration.zero);
  HabitCheckInRequestDto? lastCheckIn;

  @override
  Future<HabitCheckInMutationResponseDto> checkIn(
    HabitCheckInRequestDto request,
  ) {
    lastCheckIn = request;
    return super.checkIn(request);
  }
}

class _OldDayGateway extends FakeHabitGateway {
  _OldDayGateway({required this.detailResponse, required this.selected})
    : super(delay: Duration.zero);
  final HabitDetailResponseDto detailResponse;
  final HabitDailyStatusResponseDto selected;

  @override
  Future<HabitDetailResponseDto> detail(
    GetHabitDetailRequestDto request,
  ) async => detailResponse;

  @override
  Future<HabitDailyStatusListResponseDto> listDailyStatuses(
    ListHabitDailyStatusesRequestDto request,
  ) async => HabitDailyStatusListResponseDto(
    habitId: detailResponse.habit.id,
    startDate: selected.date,
    endDate: selected.date,
    items: [selected],
  );
}

class _PendingCapabilityGateway extends FakeHabitGateway {
  _PendingCapabilityGateway() : super(delay: Duration.zero);

  @override
  Future<HabitMutationResponseDto> create(CreateHabitRequestDto request) async {
    final base = await super.create(request);
    final detailJson = base.detail.toJson();
    (detailJson['reminder_settings']!
            as Map<String, dynamic>)['schedule_reconciliation_required'] =
        true;
    return HabitMutationResponseDto(
      detail: HabitDetailResponseDto.fromJson(detailJson),
      capability: HabitScheduleCapabilityResponseDto(
        scheduleStatus: HabitScheduleStatusContract.pendingPermission,
        scheduleReconciliationRequired: true,
        notificationPermissionStatus:
            HabitNotificationPermissionContract.denied,
        exactAlarmPermissionStatus: HabitExactAlarmPermissionContract.granted,
        degradationReasons: const [
          HabitScheduleDegradationReasonContract
              .notificationPermissionUnavailable,
        ],
      ),
    );
  }
}

class _ReconciliationDetailGateway extends FakeHabitGateway {
  _ReconciliationDetailGateway() : super(delay: Duration.zero);

  @override
  Future<HabitDetailResponseDto> detail(
    GetHabitDetailRequestDto request,
  ) async {
    final json = (await super.detail(request)).toJson();
    (json['reminder_settings']!
            as Map<String, dynamic>)['schedule_reconciliation_required'] =
        true;
    return HabitDetailResponseDto.fromJson(json);
  }
}

HabitDailyStatusResponseDto _selectedDaily(
  HabitDailyStatusResponseDto source,
  String date,
) {
  final json = source.toJson()..['date'] = date;
  final checkIn = json['check_in']! as Map<String, dynamic>;
  checkIn['check_date'] = date;
  checkIn['note'] = '第二页备注';
  return HabitDailyStatusResponseDto.fromJson(json);
}

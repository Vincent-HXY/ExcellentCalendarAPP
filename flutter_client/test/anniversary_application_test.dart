import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_form_controller.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_list_controller.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_models.dart';
import 'package:excellent_calendar/data/anniversary/fake_anniversary_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FixedAppClock clock;

  setUp(() {
    clock = FixedAppClock(DateTime(2026, 8, 6));
  });

  test('fake gateway exposes the five deterministic fixture records', () async {
    final gateway = FakeAnniversaryGateway(clock: clock);

    final result = await gateway.list(const AnniversaryListQuery());

    expect(result.items, hasLength(5));
    expect(result.items.map((item) => item.anniversary.title), [
      '周末',
      '我的生日',
      '春节',
      '与YY的约定',
      '使用滴答清单',
    ]);
    expect(result.items.map((item) => item.countdown.days), [
      2,
      15,
      184,
      217,
      398,
    ]);
  });

  test('list controller maps fake failures to retryable page state', () async {
    final gateway = FakeAnniversaryGateway(clock: clock)..failNextList();
    final controller = AnniversaryListController(gateway);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.phase, AnniversaryListPhase.error);
    expect(controller.errorMessage, '纪念日服务暂时不可用，请稍后重试');

    await controller.load();
    expect(controller.phase, AnniversaryListPhase.ready);
    expect(controller.items, hasLength(5));
  });

  test('load-more failure keeps page one and retries page two', () async {
    final gateway = FakeAnniversaryGateway(clock: clock, seedDefaults: false);
    await _seedSupportedAnniversaries(gateway, 21);
    final controller = AnniversaryListController(gateway);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.items, hasLength(20));
    expect(controller.hasMore, isTrue);

    gateway.failNextList();
    await controller.loadMore();
    expect(controller.phase, AnniversaryListPhase.ready);
    expect(controller.items, hasLength(20));
    expect(controller.loadMoreErrorMessage, '纪念日服务暂时不可用，请稍后重试');

    await controller.loadMore();
    expect(controller.items, hasLength(21));
    expect(controller.hasMore, isFalse);
    expect(controller.loadMoreErrorMessage, isNull);
  });

  test('date-only models remove time components', () {
    final draft = AnniversaryDraft(
      title: '日期边界',
      date: DateTime(2026, 8, 6, 22, 30),
      calendarType: AnniversaryCalendarType.solar,
      categoryId: null,
      note: null,
      importance: AnniversaryImportance.unimportantNotUrgent,
    );

    expect(draft.date, DateTime(2026, 8, 6));
    expect(draft.date.hour, 0);
    expect(draft.date.isUtc, isFalse);
  });

  test('lunar preview maps to the explicit unsupported failure', () async {
    final gateway = FakeAnniversaryGateway(clock: clock);
    await expectLater(
      gateway.previewCountdown(
        AnniversaryDraft(
          title: '农历纪念日',
          date: DateTime(2026, 8, 20),
          calendarType: AnniversaryCalendarType.lunar,
          categoryId: null,
          note: null,
          importance: AnniversaryImportance.unimportantNotUrgent,
        ),
        recurrence: null,
      ),
      throwsA(
        isA<AnniversaryGatewayException>()
            .having(
              (error) => error.code,
              'code',
              AnniversaryFailureCode.calendarUnsupported,
            )
            .having(anniversaryFailureMessage, 'message', '当前版本暂不支持农历'),
      ),
    );
  });

  test('preview honors the current yearly recurrence state', () async {
    final gateway = FakeAnniversaryGateway(clock: clock);
    final draft = AnniversaryDraft(
      title: '年度纪念日',
      date: DateTime(2025, 1, 1),
      calendarType: AnniversaryCalendarType.solar,
      categoryId: null,
      note: null,
      importance: AnniversaryImportance.unimportantNotUrgent,
    );

    final oneTime = await gateway.previewCountdown(draft, recurrence: null);
    final yearly = await gateway.previewCountdown(
      draft,
      recurrence: const RecurrenceDraft.yearly(),
    );

    expect(oneTime.relation, CountdownRelation.elapsed);
    expect(oneTime.targetOccurrenceDate, DateTime(2025, 1, 1));
    expect(yearly.relation, CountdownRelation.remaining);
    expect(yearly.targetOccurrenceDate, DateTime(2027, 1, 1));
  });

  test('form controller prevents duplicate submit and creates once', () async {
    final gateway = FakeAnniversaryGateway(
      clock: clock,
      seedDefaults: false,
      operationDelay: const Duration(milliseconds: 20),
    );
    final controller = AnniversaryFormController(gateway: gateway);
    addTearDown(controller.dispose);
    controller
      ..setTitle('新的纪念日')
      ..setDate(DateTime(2026, 8, 20));

    final first = controller.submit();
    final duplicate = await controller.submit();
    final created = await first;

    expect(duplicate, isNull);
    expect(created?.anniversary.title, '新的纪念日');
    expect(
      (await gateway.list(const AnniversaryListQuery())).items,
      hasLength(1),
    );
  });

  test('failed create keeps form input for retry', () async {
    final gateway = FakeAnniversaryGateway(clock: clock)..failNextCreate();
    final controller = AnniversaryFormController(gateway: gateway);
    addTearDown(controller.dispose);
    controller
      ..setTitle('保留的标题')
      ..setDate(DateTime(2026, 8, 20))
      ..setNote('保留的备注');

    final created = await controller.submit();

    expect(created, isNull);
    expect(controller.title, '保留的标题');
    expect(controller.note, '保留的备注');
    expect(controller.phase, AnniversaryFormPhase.failure);
  });
}

Future<void> _seedSupportedAnniversaries(
  FakeAnniversaryGateway gateway,
  int count,
) async {
  for (var index = 1; index <= count; index += 1) {
    await gateway.create(
      CreateAnniversaryPlan(
        anniversary: AnniversaryDraft(
          title: '纪念日 $index',
          date: DateTime(2026, 8, index),
          calendarType: AnniversaryCalendarType.solar,
          categoryId: null,
          note: null,
          importance: AnniversaryImportance.unimportantNotUrgent,
        ),
        kind: AnniversaryKind.anniversary,
        recurrence: null,
        reminders: const [],
      ),
    );
  }
}

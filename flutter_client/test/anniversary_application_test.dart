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

    final items = await gateway.list(const AnniversaryListQuery());

    expect(items, hasLength(5));
    expect(items.map((item) => item.anniversary.title), [
      '周末',
      '我的生日',
      '春节',
      '与YY的约定',
      '使用滴答清单',
    ]);
    expect(items.map((item) => item.countdown.days), [2, 15, 184, 217, 398]);
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

  test('lunar preview is explicitly unavailable', () async {
    final gateway = FakeAnniversaryGateway(clock: clock);
    final snapshot = await gateway.previewCountdown(
      AnniversaryDraft(
        title: '农历纪念日',
        date: DateTime(2026, 8, 20),
        calendarType: AnniversaryCalendarType.lunar,
        categoryId: null,
        note: null,
        importance: AnniversaryImportance.unimportantNotUrgent,
      ),
    );

    expect(snapshot.relation, CountdownRelation.unavailable);
    expect(snapshot.days, isNull);
    expect(snapshot.targetOccurrenceDate, isNull);
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
    expect(await gateway.list(const AnniversaryListQuery()), hasLength(1));
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

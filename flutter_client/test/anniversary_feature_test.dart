import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/application/anniversary/anniversary_models.dart';
import 'package:excellent_calendar/data/anniversary/fake_anniversary_gateway.dart';
import 'package:excellent_calendar/data/anniversary/fake_anniversary_share_gateway.dart';
import 'package:excellent_calendar/presentation/anniversary/pages/anniversary_detail_page.dart';
import 'package:excellent_calendar/presentation/anniversary/pages/anniversary_list_page.dart';
import 'package:excellent_calendar/presentation/anniversary/pages/create_anniversary_page.dart';
import 'package:excellent_calendar/presentation/anniversary/widgets/anniversary_list_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FixedAppClock clock;
  late FakeAnniversaryGateway gateway;
  late FakeAnniversaryShareGateway shareGateway;

  setUp(() {
    clock = FixedAppClock(DateTime(2026, 8, 6));
    gateway = FakeAnniversaryGateway(clock: clock);
    shareGateway = FakeAnniversaryShareGateway();
  });

  testWidgets('list displays all five fake anniversaries by default', (
    tester,
  ) async {
    await _setSurface(tester, const Size(412, 915));
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );

    expect(find.byType(AnniversaryListCard), findsNWidgets(5));
    expect(find.text('周末'), findsOneWidget);
    expect(find.text('我的生日'), findsOneWidget);
    expect(find.text('春节'), findsOneWidget);
    expect(find.text('与YY的约定'), findsOneWidget);
    expect(find.text('使用滴答清单'), findsOneWidget);

    final allChip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('anniversary-filter-all')),
    );
    expect(allChip.selected, isTrue);
  });

  testWidgets('anniversary and countdown filters change visible records', (
    tester,
  ) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );

    await tester.tap(
      find.byKey(const ValueKey('anniversary-filter-anniversary')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnniversaryListCard), findsNWidgets(2));
    expect(find.text('与YY的约定'), findsOneWidget);
    expect(find.text('使用滴答清单'), findsOneWidget);
    expect(find.text('周末'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('anniversary-filter-countdown')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnniversaryListCard), findsOneWidget);
    expect(find.text('周末'), findsOneWidget);
  });

  testWidgets('card opens detail with elapsed copy and 217 days', (
    tester,
  ) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );

    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-promise')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AnniversaryDetailPage), findsOneWidget);
    expect(find.text('217'), findsOneWidget);
    expect(find.textContaining('已经'), findsOneWidget);
    expect(find.text('与YY的约定'), findsOneWidget);
  });

  testWidgets('detail note, theme and share actions are wired', (tester) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );
    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-promise')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('备注'));
    await tester.tap(find.byTooltip('备注'));
    await tester.pumpAndSettle();
    expect(find.text('记得那天我们约好，以后每一年都要一起认真生活。'), findsOneWidget);
    Navigator.of(tester.element(find.text('记得那天我们约好，以后每一年都要一起认真生活。'))).pop();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byTooltip('主题'));
    await tester.tap(find.byTooltip('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('主题 2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byTooltip('分享'));
    await tester.tap(find.byTooltip('分享'));
    await tester.pump();
    expect(shareGateway.shareCallCount, 1);
    expect(find.text('分享接口已预留'), findsOneWidget);
  });

  testWidgets('detail edit reuses the form and updates visible data', (
    tester,
  ) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );
    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-promise')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑纪念日'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('anniversary-title-field')),
      '与YY的新约定',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('anniversary-save-button')),
    );
    await tester.tap(find.byKey(const ValueKey('anniversary-save-button')));
    await tester.pumpAndSettle();

    expect(find.byType(AnniversaryDetailPage), findsOneWidget);
    expect(find.text('与YY的新约定'), findsOneWidget);
  });

  testWidgets('FAB opens create page and empty title cannot save', (
    tester,
  ) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );

    await tester.tap(find.byKey(const ValueKey('anniversary-add-button')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateAnniversaryPage), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('anniversary-save-button')),
    );
    await tester.tap(find.byKey(const ValueKey('anniversary-save-button')));
    await tester.pump();

    expect(find.text('请输入纪念日名称'), findsOneWidget);
    expect(find.text('请选择纪念日日期'), findsOneWidget);
    expect(find.byType(CreateAnniversaryPage), findsOneWidget);
  });

  testWidgets(
    'title and date create a record that remains in the shared gateway',
    (tester) async {
      await _pumpList(
        tester,
        clock: clock,
        gateway: gateway,
        shareGateway: shareGateway,
      );
      await tester.tap(find.byKey(const ValueKey('anniversary-add-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('anniversary-title-field')),
        '毕业纪念日',
      );
      await tester.tap(find.byKey(const ValueKey('anniversary-date-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('anniversary-save-button')),
      );
      await tester.tap(find.byKey(const ValueKey('anniversary-save-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(AnniversaryListPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AnniversaryListCard),
          matching: find.text('毕业纪念日'),
        ),
        findsOneWidget,
      );
      final stored = await gateway.list(const AnniversaryListQuery());
      expect(stored, hasLength(6));
      expect(stored.first.anniversary.title, '毕业纪念日');
    },
  );

  testWidgets('delete removes an anniversary from the shared list', (
    tester,
  ) async {
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );
    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-weekend')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.byType(AnniversaryListPage), findsOneWidget);
    expect(find.text('周末'), findsNothing);
    expect(find.byType(AnniversaryListCard), findsNWidgets(4));
  });

  testWidgets('empty and error states expose recovery actions', (tester) async {
    final emptyGateway = FakeAnniversaryGateway(
      clock: clock,
      seedDefaults: false,
    );
    await _pumpList(
      tester,
      clock: clock,
      gateway: emptyGateway,
      shareGateway: shareGateway,
    );
    expect(find.text('这里还没有纪念日'), findsOneWidget);

    gateway.failNextList();
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );
    expect(find.text('纪念日加载失败'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(find.text('纪念日加载失败'), findsNothing);
    expect(find.text('周末'), findsOneWidget);
  });

  testWidgets('360x800 layout has no overflow', (tester) async {
    await _setSurface(tester, const Size(360, 800));
    await _pumpList(
      tester,
      clock: clock,
      gateway: gateway,
      shareGateway: shareGateway,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-promise')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.3 text scale keeps key list and detail layout bounded', (
    tester,
  ) async {
    await _setSurface(tester, const Size(412, 915));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: AnniversaryListPage(
          key: UniqueKey(),
          gateway: gateway,
          shareGateway: shareGateway,
          clock: clock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.byKey(const ValueKey('anniversary-card-fake-tick-list')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('398'), findsOneWidget);
  });
}

Future<void> _pumpList(
  WidgetTester tester, {
  required FixedAppClock clock,
  required FakeAnniversaryGateway gateway,
  required FakeAnniversaryShareGateway shareGateway,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AnniversaryListPage(
        key: UniqueKey(),
        gateway: gateway,
        shareGateway: shareGateway,
        clock: clock,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

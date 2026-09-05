import 'package:excellent_calendar/app/localization/app_localization.dart';
import 'package:excellent_calendar/application/search/search_controller.dart';
import 'package:excellent_calendar/application/search/search_date_filter.dart';
import 'package:excellent_calendar/application/search/search_models.dart';
import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';
import 'package:excellent_calendar/presentation/search/pages/search_page.dart';
import 'package:excellent_calendar/presentation/search/search_design_tokens.dart';
import 'package:excellent_calendar/presentation/search/widgets/highlighted_search_text.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_search_gateway.dart';
import 'support/search_test_support.dart';

void main() {
  testWidgets(
    'idle history supports long-press management, delete and clear undo',
    (tester) async {
      final gateway = FakeSearchGateway(
        initialHistory: SearchHistoryResponseDto(
          revision: 2,
          items: const ['项目', '会议'],
        ),
        onQuery: (request) async => searchResponse(request),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      expect(find.text('搜索'), findsOneWidget);
      expect(find.text('最近搜索'), findsOneWidget);
      await tester.longPress(find.text('项目'));
      await tester.pumpAndSettle();
      expect(controller.state.history.mode, SearchHistoryMode.managing);
      expect(find.byTooltip('删除 项目'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('搜索历史已清空'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('项目'), findsOneWidget);

      await tester.pump(const Duration(seconds: 7));
      expect(find.text('项目'), findsOneWidget);
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      expect(find.text('搜索历史已清空'), findsOneWidget);
      await controller.setActive(false);
      await tester.pump();
      expect(find.text('搜索历史已清空'), findsNothing);
    },
  );

  testWidgets(
    'focusing the search field hides the title and moves the field upward',
    (tester) async {
      final gateway = FakeSearchGateway(
        initialHistory: SearchHistoryResponseDto(
          revision: 1,
          items: const ['会议'],
        ),
        onQuery: (request) async => searchResponse(request),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('search-field'));
      final initialTop = tester.getTopLeft(field).dy;
      expect(find.byKey(const ValueKey('search-large-title')), findsOneWidget);

      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getTopLeft(field).dy, lessThan(initialTop));

      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('search-large-title')).hitTestable(),
        findsNothing,
      );
      expect(tester.getTopLeft(field).dy, lessThan(initialTop - 20));
      expect(find.byTooltip('筛选'), findsOneWidget);
    },
  );

  testWidgets('history chips use the compact visual height', (tester) async {
    final gateway = FakeSearchGateway(
      initialHistory: SearchHistoryResponseDto(
        revision: 1,
        items: const ['会议'],
      ),
      onQuery: (request) async => searchResponse(request),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    final chip = find.byKey(const ValueKey('search-history-chip-会议'));
    expect(tester.getSize(chip).height, 28);
    final palette = SearchPalette.of(tester.element(chip));
    final decoration =
        tester.widget<Container>(chip).decoration! as BoxDecoration;
    expect(decoration.color, palette.historyChip);
    expect(
      (decoration.border! as Border).top.color,
      palette.historyChipOutline,
    );
    await tester.tap(chip);
    await tester.pump();
    expect(controller.state.rawKeyword, '会议');
  });

  testWidgets('clear-history undo expires instead of remaining on screen', (
    tester,
  ) async {
    final gateway = FakeSearchGateway(
      initialHistory: SearchHistoryResponseDto(
        revision: 2,
        items: const ['项目', '会议'],
      ),
      onQuery: (request) async => searchResponse(request),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('搜索历史已清空'), findsOneWidget);

    await tester.pump(const Duration(seconds: 7));
    expect(find.text('搜索历史已清空'), findsNothing);
    expect(controller.state.history.undoItems, isNull);
  });

  testWidgets('Search host resolves its Material controls in Chinese', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final gateway = FakeSearchGateway(
      onQuery: (request) async => searchResponse(request),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();

    expect(
      Localizations.localeOf(
        tester.element(find.byKey(const ValueKey('search-field'))),
      ),
      const Locale('zh', 'CN'),
    );

    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    expect(find.text('选择开始日期'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('选择开始日期')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\bto\b')), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('选择结束日期'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('选择结束日期')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\bto\b')), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看结果'));
    await tester.pumpAndSettle();
    expect(controller.state.filters.date.preset, SearchDatePreset.custom);
    expect(
      controller.state.filters.date.dateFrom,
      controller.state.today.format(),
    );
    expect(
      controller.state.filters.date.dateToExclusive,
      controller.state.today.addDays(1).format(),
    );
    expect(find.byTooltip('移除时间筛选'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsNothing);
    semantics.dispose();
  });

  testWidgets(
    'keyboard search renders fixed three-section order and opens a typed route',
    (tester) async {
      final gateway = FakeSearchGateway(
        onQuery: (request) async => searchResponse(
          request,
          items: {
            SearchTargetType.event: [searchEvent(1), searchEvent(2)],
            SearchTargetType.habit: [searchHabit(1)],
            SearchTargetType.anniversary: [searchAnniversary(1)],
          },
        ),
      );
      final opened = <SearchItemDto>[];
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          controller,
          resultNavigator: (_, item) async {
            opened.add(item);
            return SearchDetailMutation.unchanged;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('search-field')), '项目');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final eventHeader = find.text('日程（2）');
      final habitHeader = find.text('习惯（1）');
      final anniversaryHeader = find.text('纪念日（1）');
      final eventY = tester.getTopLeft(eventHeader).dy;
      final habitY = tester.getTopLeft(habitHeader).dy;
      final anniversaryY = tester.getTopLeft(anniversaryHeader).dy;
      expect(eventY, lessThan(habitY));
      expect(habitY, lessThan(anniversaryY));
      expect(find.text('1 条'), findsNothing);

      final palette = SearchPalette.of(tester.element(eventHeader));
      final scheme = Theme.of(tester.element(eventHeader)).colorScheme;
      final expectedColors = [
        palette.sectionColor(scheme, 0),
        palette.sectionColor(scheme, 1),
        palette.sectionColor(scheme, 2),
      ];
      final headers = [eventHeader, habitHeader, anniversaryHeader];
      final resultTexts = ['项目会议 1', '晨间复盘 1', '项目周年 1'];
      for (var index = 0; index < headers.length; index++) {
        expect(
          tester.widget<Text>(headers[index]).style?.color,
          expectedColors[index],
        );
        final highlighted = find.byWidgetPredicate(
          (widget) =>
              widget is HighlightedSearchText &&
              widget.text == resultTexts[index],
        );
        expect(
          tester.widget<HighlightedSearchText>(highlighted).highlightColor,
          expectedColors[index],
        );
        final headerFontSize =
            tester.widget<Text>(headers[index]).style?.fontSize ?? 16;
        final resultFontSize = tester
            .widget<HighlightedSearchText>(highlighted)
            .style
            ?.fontSize;
        expect(resultFontSize, closeTo(14, 0.001));
        expect(
          resultFontSize,
          closeTo((headerFontSize + headerFontSize * 0.75) / 2, 0.001),
        );
        final highlightColors = SearchDesignTokens.highlightColors(
          scheme,
          expectedColors[index],
        );
        expect(highlightColors.foreground, expectedColors[index]);
        expect(
          highlightColors.background,
          isNot(equals(const Color(0x66FFD54F))),
        );
      }

      final firstEventTop = tester.getTopLeft(find.text('项目会议 1')).dy;
      final secondEventTop = tester.getTopLeft(find.text('项目会议 2')).dy;
      expect(secondEventTop - firstEventTop, lessThanOrEqualTo(61));

      await tester.tap(find.text('项目会议 1'));
      await tester.pumpAndSettle();
      expect(opened.single, isA<SearchEventItemDto>());
    },
  );

  testWidgets(
    'staged filter can be dismissed, reset and applied without mutating early',
    (tester) async {
      final gateway = FakeSearchGateway(
        onQuery: (request) async => searchResponse(request),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('筛选'));
      await tester.pumpAndSettle();
      expect(find.text('时间'), findsOneWidget);
      expect(find.text('类型'), findsOneWidget);
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('完成状态'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('排序'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('排序'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('今天')),
        alignment: 0.5,
        duration: Duration.zero,
      );
      await tester.pump();
      await tester.tap(find.text('今天'));
      await tester.tapAt(const Offset(8, 400));
      await tester.pumpAndSettle();
      expect(controller.state.filters.activeGroupCount, 0);

      await tester.tap(find.byTooltip('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今天'));
      await tester.tap(find.text('查看结果'));
      await tester.pumpAndSettle();
      expect(controller.state.filters.activeGroupCount, 1);
    },
  );

  testWidgets(
    'result card aligns content and reserves its only chevron for more results',
    (tester) async {
      final gateway = FakeSearchGateway(
        onQuery: (request) async => searchResponse(
          request,
          items: {
            SearchTargetType.event: [
              for (var index = 1; index <= 20; index++) searchEvent(index),
            ],
          },
          totals: const {SearchTargetType.event: 23},
          hasMore: const {SearchTargetType.event},
        ),
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('search-field')), '项目');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final section = find.byKey(const ValueKey('search-section-event'));
      expect(find.text('还有 3 个日程'), findsOneWidget);
      expect(
        find.descendant(
          of: section,
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.byType(Divider)),
        findsOneWidget,
      );
      final headerLeft = tester.getTopLeft(find.text('日程（23）')).dx;
      final resultLeft = tester.getTopLeft(find.text('项目会议 1')).dx;
      expect((headerLeft - resultLeft).abs(), lessThan(2));
    },
  );

  testWidgets(
    '360dp and 200 percent text has no overflow in light or dark themes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        final gateway = FakeSearchGateway(
          initialHistory: SearchHistoryResponseDto(
            revision: 1,
            items: const ['这是一个用于验证超长文字与大字体布局的搜索历史关键词'],
          ),
          onQuery: (request) async => searchResponse(request),
        );
        final controller = _controller(gateway);
        await controller.initialize();
        await controller.setActive(true);
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: _app(controller, brightness: brightness),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.takeException(), isNull);
        controller.dispose();
      }
    },
  );

  testWidgets('compact result cards keep 200 percent text overflow-free', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeSearchGateway(
      onQuery: (request) async => searchResponse(
        request,
        items: {
          SearchTargetType.event: [searchEvent(1)],
          SearchTargetType.habit: [searchHabit(1)],
          SearchTargetType.anniversary: [searchAnniversary(1)],
        },
      ),
    );
    final controller = _controller(gateway);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: _app(controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('search-field')), '项目');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'app resume does not reactivate Search after its tab became inactive',
    (tester) async {
      var timezone = searchTimezone;
      final gateway = FakeSearchGateway(
        onQuery: (request) async => searchResponse(request),
      );
      final controller = SearchController(
        gateway: gateway,
        historyGateway: gateway,
        timezoneProvider: () async => timezone,
        categoryRepository: FakeSearchCategoryRepository(),
        nowProvider: () => DateTime(2026, 8, 31, 9),
        clockGuardInterval: const Duration(days: 1),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      controller.updateText('项目', isComposing: false);
      await controller.submit();
      await controller.setActive(false);

      timezone = 'Europe/Paris';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(controller.state.timezone, searchTimezone);
      expect(gateway.queryRequests, hasLength(1));
    },
  );
}

SearchController _controller(FakeSearchGateway gateway) => SearchController(
  gateway: gateway,
  historyGateway: gateway,
  timezoneProvider: () async => searchTimezone,
  categoryRepository: FakeSearchCategoryRepository(),
  nowProvider: () => DateTime(2026, 8, 31, 9),
  clockGuardInterval: const Duration(days: 1),
);

Widget _app(
  SearchController controller, {
  SearchResultNavigator? resultNavigator,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  locale: excellentCalendarLocale,
  localizationsDelegates: excellentCalendarLocalizationsDelegates,
  supportedLocales: excellentCalendarSupportedLocales,
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
  ),
  home: SearchPage(controller: controller, resultNavigator: resultNavigator),
);

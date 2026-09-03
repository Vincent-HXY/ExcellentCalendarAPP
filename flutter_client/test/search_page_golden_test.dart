import 'package:excellent_calendar/application/search/search_controller.dart';
import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_response_dtos.dart';
import 'package:excellent_calendar/presentation/search/pages/search_page.dart';
import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_search_gateway.dart';
import 'support/search_test_support.dart';

void main() {
  const surface = ValueKey('search-golden-surface');

  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.textScaleFactorTestValue = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearTextScaleFactorTestValue();
  });

  testWidgets('light history golden', (tester) async {
    final controller = _controller(
      FakeSearchGateway(
        initialHistory: SearchHistoryResponseDto(
          revision: 2,
          items: const ['项目 MEETING', '年度回顾', '晨间复盘'],
        ),
        onQuery: (request) async => searchResponse(request),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.setActive(true);
    await _pump(tester, controller, Brightness.light, surface);
    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/search_history_light.png'),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} three sections golden', (tester) async {
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
      await controller.initialize();
      await controller.setActive(true);
      controller.updateText('项目', isComposing: false);
      await controller.submit();
      await _pump(tester, controller, brightness, surface);
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/search_ready_${brightness.name}.png'),
      );
    });
  }

  testWidgets('dark filter popover golden', (tester) async {
    final controller = _controller(
      FakeSearchGateway(onQuery: (request) async => searchResponse(request)),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.setActive(true);
    await _pump(tester, controller, Brightness.dark, surface);
    await tester.tap(find.byTooltip('筛选'));
    await tester.pump(const Duration(milliseconds: 220));
    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/search_filter_dark.png'),
    );
  });
}

SearchController _controller(FakeSearchGateway gateway) => SearchController(
  gateway: gateway,
  historyGateway: gateway,
  timezoneProvider: () async => searchTimezone,
  categoryRepository: FakeSearchCategoryRepository(),
  nowProvider: () => DateTime(2026, 8, 31, 9),
  clockGuardInterval: const Duration(days: 1),
);

Future<void> _pump(
  WidgetTester tester,
  SearchController controller,
  Brightness brightness,
  Key surface,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: surface,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: brightness,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: SearchPage(controller: controller),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

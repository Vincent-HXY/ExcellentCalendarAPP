import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/native_contract/category/category_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/runtime/local_wall_date_time.dart';
import 'package:excellent_calendar/presentation/event_detail/models/event_detail_ui_state.dart';
import 'package:excellent_calendar/presentation/event_detail/pages/event_detail_page.dart';
import 'package:excellent_calendar/presentation/inbox/components/task_list_item.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('event detail presents preview data and delegates actions', (
    tester,
  ) async {
    var moreCalls = 0;
    var editCalls = 0;
    var completeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EventDetailPage(
          state: EventDetailUiState.preview(),
          onMore: () => moreCalls += 1,
          onEdit: () => editCalls += 1,
          onComplete: () {
            completeCalls += 1;
            return const EventDetailCompletionResult.success();
          },
        ),
      ),
    );

    expect(find.text('\u65e5\u7a0b\u8be6\u60c5'), findsOneWidget);
    expect(find.text('\u4ea7\u54c1\u9700\u6c42\u8bc4\u5ba1'), findsOneWidget);
    expect(find.text('\u65f6\u95f4\u5b89\u6392'), findsOneWidget);
    expect(find.text('\u8be6\u60c5\u4e0e\u5907\u6ce8'), findsOneWidget);
    expect(find.text('\u72b6\u6001\u4e0e\u53c2\u4e0e'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.tap(find.text('\u7f16\u8f91'));
    await tester.tap(find.text('\u5b8c\u6210'));
    await tester.pump();

    expect(moreCalls, 1);
    expect(editCalls, 1);
    expect(completeCalls, 1);
  });

  testWidgets('event detail has no layout exception at common phone widths', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in [
      const Size(360, 640),
      const Size(393, 852),
      const Size(411, 891),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailPage.preview(
            eventId: 'event-${size.width}x${size.height}',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'size: $size');
    }
  });

  testWidgets('event detail renders all three category projection states', (
    tester,
  ) async {
    final cases = <({EventDetailUiState state, String label})>[
      (state: _categoryState(), label: '未分类'),
      (
        state: _categoryState(
          categoryId: _categoryId,
          category: _activeCategory,
        ),
        label: '工作',
      ),
      (state: _categoryState(categoryId: _categoryId), label: '分类不可用或已删除'),
    ];

    for (final testCase in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailPage(state: testCase.state, canComplete: false),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('event-category-status')),
        findsOneWidget,
      );
      expect(find.text(testCase.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('category UI projection rejects a mismatched aggregate', () {
    expect(
      () => _categoryState(
        categoryId: _categoryId,
        category: CategoryResponseDto(
          id: '40000000-0000-4000-8000-000000000002',
          name: '错误分类',
          description: null,
          color: '#39AFBD',
          icon: null,
          sortOrder: 1,
          createdAt: DateTime.utc(2026, 8, 11),
          updatedAt: DateTime.utc(2026, 8, 11),
          deletedAt: null,
        ),
      ),
      throwsFormatException,
    );
  });

  testWidgets('editing shows the temporary unavailable feedback', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: EventDetailPage.preview()));

    await tester.tap(find.text('\u7f16\u8f91'));
    await tester.pump();

    expect(
      find.text(
        '\u7f16\u8f91\u529f\u80fd\u6682\u4e0d\u652f\u6301\uff0c\u540e\u7eed\u5f00\u53d1\u518d\u5b8c\u5584',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'completion failure stays on the detail page and shows feedback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailPage(
            state: EventDetailUiState.preview(),
            onComplete: () => const EventDetailCompletionResult.failure(
              'Complete event failed.',
            ),
          ),
        ),
      );

      await tester.tap(find.text('\u5b8c\u6210'));
      await tester.pump();

      expect(find.text('Complete event failed.'), findsOneWidget);
      expect(find.byType(EventDetailPage), findsOneWidget);
    },
  );

  testWidgets('tapping task content opens detail without completing it', (
    tester,
  ) async {
    var detailTapCount = 0;
    var completionCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskListItem(
            task: const InboxTaskViewData(
              id: 'event-1',
              title: 'Open schedule details',
              importance: TaskImportance.unimportantNotUrgent,
              isCompleted: false,
            ),
            showDivider: false,
            onTap: () => detailTapCount += 1,
            onComplete: () async {
              completionCount += 1;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open schedule details'));
    await tester.pump();

    expect(detailTapCount, 1);
    expect(completionCount, 0);
  });
}

const _categoryId = '40000000-0000-4000-8000-000000000001';

final _activeCategory = CategoryResponseDto(
  id: _categoryId,
  name: '工作',
  description: null,
  color: '#39AFBD',
  icon: null,
  sortOrder: 1,
  createdAt: DateTime.utc(2026, 8, 11),
  updatedAt: DateTime.utc(2026, 8, 11),
  deletedAt: null,
);

EventDetailUiState _categoryState({
  String? categoryId,
  CategoryResponseDto? category,
}) {
  return EventDetailUiState.fromEvent(
    EventResponseDto(
      id: 'event-category-state',
      title: '分类回显',
      content: null,
      startAt: DateTime.utc(2026, 8, 11, 9),
      endAt: DateTime.utc(2026, 8, 11, 10),
      startDate: null,
      endDate: null,
      isAllDay: false,
      hasRecurrence: false,
      status: 'active',
      recurrenceId: null,
      recurrenceRevision: null,
      categoryId: categoryId,
      timezone: 'Asia/Shanghai',
      source: 'manual',
      createdAt: DateTime.utc(2026, 8, 11),
      updatedAt: DateTime.utc(2026, 8, 11),
    ),
    localizedTimeRange: LocalizedTimeRange(
      start: LocalWallDateTime.parse('2026-08-11T17:00:00'),
      end: LocalWallDateTime.parse('2026-08-11T18:00:00'),
      timezone: 'Asia/Shanghai',
    ),
    displayStatusOverride: EventDisplayStatus.pending,
    category: category,
  );
}

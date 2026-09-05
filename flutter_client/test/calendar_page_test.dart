import 'dart:async';

import 'package:excellent_calendar/application/calendar/calendar_controller.dart';
import 'package:excellent_calendar/application/calendar/calendar_date_math.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_contract_enums.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_response_dtos.dart';
import 'package:excellent_calendar/presentation/calendar/calendar_page.dart';
import 'package:excellent_calendar/presentation/calendar/widgets/calendar_grid.dart';
import 'package:excellent_calendar/presentation/calendar/widgets/calendar_header.dart';
import 'package:excellent_calendar/presentation/inbox/inbox_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/calendar_test_support.dart';

void main() {
  group('CalendarPage responsive Material 3 surface', () {
    testWidgets('renders 360dp light and dark surfaces without overflow', (
      tester,
    ) async {
      await _setScreen(tester);
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await _pumpCalendar(tester, brightness: brightness);

        expect(find.byKey(const ValueKey('calendar-page')), findsOneWidget);
        expect(find.text('日程'), findsWidgets);
        expect(find.text('习惯'), findsWidgets);
        expect(find.text('纪念日'), findsWidgets);
        expect(
          Theme.of(tester.element(find.byType(CalendarPage))).brightness,
          brightness,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
      'uses the schedule background and compact Chinese month header',
      (tester) async {
        await _setScreen(tester);
        await _pumpCalendar(tester);

        final scaffold = tester.widget<Scaffold>(
          find.byKey(const ValueKey('calendar-page')),
        );
        expect(scaffold.backgroundColor, InboxColors.pageBackground);
        expect(find.text('八月'), findsOneWidget);
        expect(find.text('2026年8月'), findsNothing);

        final title = tester.widget<Text>(find.text('八月'));
        expect(title.style?.fontSize, 16);
        expect(
          find.descendant(
            of: find.byType(CalendarHeader),
            matching: find.byIcon(Icons.chevron_left_rounded),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(CalendarHeader),
            matching: find.byIcon(Icons.chevron_right_rounded),
          ),
          findsNothing,
        );
        expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
        expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
        expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
        expect(
          tester
              .getCenter(
                find.byKey(const ValueKey('calendar-year-month-button')),
              )
              .dy,
          tester
              .getCenter(find.byKey(const ValueKey('calendar-mode-button')))
              .dy,
        );

        final harness = await _pumpCalendar(tester);
        await harness.controller.navigatePeriod(1);
        await tester.pumpAndSettle();
        expect(find.text('九月'), findsOneWidget);
        expect(find.text('2026年9月'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders at 200 percent text scale without overflow', (
      tester,
    ) async {
      await _setScreen(tester);
      await _pumpCalendar(tester, textScale: 2);

      expect(
        find.byKey(const ValueKey('calendar-year-month-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-timeline-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-settings-button')),
        findsOneWidget,
      );
      expect(find.text('日程 1'), findsOneWidget);
      final fabRect = tester.getRect(
        find.byKey(const ValueKey('calendar-create-fab')),
      );
      expect(fabRect.size, const Size.square(58));
      expect(
        find.byKey(const ValueKey('calendar-create-action-bar')),
        findsNothing,
      );
      final bodyRect = tester.getRect(find.byType(CustomScrollView));
      await tester.ensureVisible(
        find.byKey(ValueKey(calendarHabit(1, '2026-08-31').identityKey)),
      );
      await tester.pumpAndSettle();
      final habitRect = tester
          .getRect(
            find.byKey(ValueKey(calendarHabit(1, '2026-08-31').identityKey)),
          )
          .intersect(bodyRect);
      expect(fabRect.overlaps(habitRect), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'create action never intersects a card, empty state, or load-more control',
      (tester) async {
        await _setScreen(tester);

        Future<void> expectVisibleWithoutFabOverlap(Finder content) async {
          await tester.ensureVisible(content);
          await tester.pumpAndSettle();
          final viewport = tester.getRect(find.byType(CustomScrollView));
          final visibleContent = tester.getRect(content).intersect(viewport);
          final fab = tester.getRect(
            find.byKey(const ValueKey('calendar-create-fab')),
          );
          expect(visibleContent.isEmpty, isFalse);
          expect(fab.overlaps(visibleContent), isFalse);
        }

        await _pumpCalendar(tester);
        await tester.tap(find.byKey(const ValueKey('calendar-mode-button')));
        await tester.pumpAndSettle();
        await expectVisibleWithoutFabOverlap(
          find.byKey(ValueKey(calendarEvent(1).identityKey)),
        );

        await _pumpCalendar(
          tester,
          onPage: (request) async =>
              calendarPageResponse(request: request, items: const []),
        );
        await expectVisibleWithoutFabOverlap(
          find.byKey(const ValueKey('calendar-empty-state')),
        );

        await _pumpCalendar(
          tester,
          onPage: (request) async => calendarPageResponse(
            request: request,
            items: calendarItemsFor(request.section, request.date),
            hasMore: request.section == CalendarSection.event,
            nextCursor: request.section == CalendarSection.event
                ? calendarCursorA
                : null,
          ),
        );
        await expectVisibleWithoutFabOverlap(
          find.byKey(const ValueKey('calendar-load-more-event')),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('calendar grid blends into the page background', (
      tester,
    ) async {
      await _setScreen(tester);
      await _pumpCalendar(tester);

      expect(
        find.byKey(const ValueKey('calendar-grid-canvas')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Padding>(find.byKey(const ValueKey('calendar-grid-canvas')))
            .padding,
        const EdgeInsets.fromLTRB(4, 4, 4, 2),
      );
    });

    testWidgets('completed items lead four collapsible schedule-style cards', (
      tester,
    ) async {
      await _setScreen(tester, height: 1000);
      await _pumpCalendar(
        tester,
        onPage: (request) async => calendarPageResponse(
          request: request,
          items: switch (request.section) {
            CalendarSection.event => [
              _eventWithStatus(
                91,
                title: '已完成日程',
                status: CalendarEventItemStatus.completed,
              ),
              calendarEvent(1),
            ],
            CalendarSection.habit => [
              _habitWithStatus(
                92,
                request.date,
                CalendarHabitItemStatus.done,
                checkInId: calendarUuid(592),
                completed: 100,
                target: 100,
                unit: '页',
              ),
              calendarHabit(1, request.date),
            ],
            CalendarSection.anniversary => [
              calendarAnniversary(1, request.date),
            ],
          },
        ),
      );

      const cardKeys = [
        'calendar-section-card-completed',
        'calendar-section-card-event',
        'calendar-section-card-habit',
        'calendar-section-card-anniversary',
      ];
      final tops = [
        for (final key in cardKeys)
          tester.getTopLeft(find.byKey(ValueKey(key))).dy,
      ];
      expect(tops, orderedEquals(tops.toList()..sort()));
      for (final key in cardKeys) {
        final cards = tester.widgetList<Container>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Container),
          ),
        );
        expect(
          cards.any(
            (card) =>
                card.decoration is BoxDecoration &&
                (card.decoration! as BoxDecoration).color ==
                    InboxColors.surface,
          ),
          isTrue,
        );
      }

      expect(find.text('已完成日程'), findsNothing);
      expect(find.text('习惯状态 92'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('calendar-section-toggle-completed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已完成日程'), findsOneWidget);
      expect(find.text('习惯状态 92'), findsOneWidget);
      expect(find.text('日程 1'), findsOneWidget);
      expect(find.text('习惯 1'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('calendar-section-toggle-event')),
      );
      await tester.pumpAndSettle();
      expect(find.text('日程 1'), findsNothing);
      expect(find.text('已完成日程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides empty groups after all remaining work is completed', (
      tester,
    ) async {
      await _setScreen(tester, height: 900);
      await _pumpCalendar(
        tester,
        onPage: (request) async => calendarPageResponse(
          request: request,
          items: switch (request.section) {
            CalendarSection.event => [
              _eventWithStatus(
                93,
                title: '刚完成的日程',
                status: CalendarEventItemStatus.completed,
              ),
            ],
            CalendarSection.habit => [
              _habitWithStatus(
                94,
                request.date,
                CalendarHabitItemStatus.done,
                checkInId: calendarUuid(594),
                completed: 1,
                target: 1,
                unit: '次',
              ),
            ],
            CalendarSection.anniversary => const [],
          },
        ),
      );

      expect(
        find.byKey(const ValueKey('calendar-section-card-completed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-event')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-habit')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-anniversary')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('calendar-empty-state')), findsNothing);
    });

    testWidgets('reduce-motion makes Calendar transitions immediate', (
      tester,
    ) async {
      await _setScreen(tester);
      await _pumpCalendar(tester, disableAnimations: true);

      expect(
        find.descendant(
          of: find.byType(CalendarGrid),
          matching: find.byType(AnimatedSize),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(CalendarGrid),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('date and cards expose complete accessible semantics', (
      tester,
    ) async {
      await _setScreen(tester);
      final semantics = tester.ensureSemantics();
      await _pumpCalendar(tester);

      expect(
        find.bySemanticsLabel('2026年8月31日，星期一，今天，已选中，有日程，有待完成习惯，有纪念日'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('日程，日程 1')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('习惯，习惯 1')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('纪念日，纪念日 1')), findsOneWidget);
      semantics.dispose();
    });
  });

  group('CalendarPage gesture arbitration', () {
    testWidgets('month view always reserves six stable rows', (tester) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-mode-button')));
      await tester.pumpAndSettle();
      await harness.controller.navigatePeriod(1);
      await tester.pumpAndSettle();

      final surface = find.byKey(
        const ValueKey('calendar-period-drag-surface'),
      );
      expect(tester.getSize(surface).height, 52 * 6);
      final sixthRowDate = find.byKey(
        const ValueKey('calendar-date-2026-10-05'),
      );
      expect(sixthRowDate, findsOneWidget);
      expect(
        tester
            .widget<Opacity>(
              find.descendant(of: sixthRowDate, matching: find.byType(Opacity)),
            )
            .opacity,
        0.58,
      );
    });

    testWidgets('vertical drag on the upper calendar expands it naturally', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      final surface = find.byKey(
        const ValueKey('calendar-period-drag-surface'),
      );
      final beforeHandle = tester.getCenter(
        find.byKey(const ValueKey('calendar-resize-handle')),
      );
      expect(tester.getSize(surface).height, 52);

      await tester.drag(
        find.byKey(const ValueKey('calendar-upper-gesture-surface')),
        const Offset(0, 190),
      );
      await tester.pumpAndSettle();

      expect(harness.controller.state.viewMode, CalendarViewMode.month);
      expect(tester.getSize(surface).height, 52 * 6);
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('calendar-resize-handle')))
            .dy,
        greaterThan(beforeHandle.dy + 200),
      );
    });

    testWidgets('divider drag keeps the selected week visible while folding', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-mode-button')));
      await tester.pumpAndSettle();
      await harness.controller.navigatePeriod(1);
      await tester.pumpAndSettle();

      final handle = find.byKey(const ValueKey('calendar-resize-handle'));
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -170));
      await tester.pump();

      final surfaceRect = tester.getRect(
        find.byKey(const ValueKey('calendar-period-drag-surface')),
      );
      final selectedRect = tester.getRect(
        find.byKey(const ValueKey('calendar-date-2026-09-30')),
      );
      expect(surfaceRect.height, inExclusiveRange(52, 52 * 6));
      expect(selectedRect.intersect(surfaceRect).isEmpty, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.controller.state.viewMode, CalendarViewMode.week);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('calendar-period-drag-surface')))
            .height,
        52,
      );
      expect(
        find.byKey(const ValueKey('calendar-date-2026-09-30')),
        findsOneWidget,
      );
    });

    testWidgets(
      'divider drag keeps selected-day content visible while the range changes',
      (tester) async {
        await _setScreen(tester);
        final rangeReload = Completer<CalendarRangeSummaryResponseDto>();
        final pageReloads = {
          for (final section in CalendarSection.values)
            section: Completer<CalendarDayItemPageDto>(),
        };
        var rangeCalls = 0;
        final harness = await _pumpCalendar(
          tester,
          onRange: (request) {
            rangeCalls += 1;
            if (rangeCalls == 1) {
              return Future.value(calendarRangeResponse(request: request));
            }
            return rangeReload.future;
          },
          onPage: (request) {
            if (request.snapshotToken == calendarSnapshotA) {
              return Future.value(calendarPageResponse(request: request));
            }
            return pageReloads[request.section]!.future;
          },
        );
        expect(find.text('日程 1'), findsOneWidget);
        expect(harness.gateway.pageRequests, hasLength(3));

        await tester.drag(
          find.byKey(const ValueKey('calendar-resize-handle')),
          const Offset(0, 190),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(harness.controller.state.viewMode, CalendarViewMode.month);
        expect(find.text('日程 1'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-section-skeleton')),
          findsNothing,
        );
        expect(harness.gateway.pageRequests, hasLength(3));

        rangeReload.complete(
          calendarRangeResponse(
            request: harness.gateway.rangeRequests.last,
            snapshotToken: calendarSnapshotB,
          ),
        );
        await tester.pump();
        expect(harness.gateway.pageRequests, hasLength(6));
        expect(find.text('日程 1'), findsOneWidget);

        for (final request in harness.gateway.pageRequests.skip(3)) {
          pageReloads[request.section]!.complete(
            calendarPageResponse(request: request),
          );
        }
        await tester.pump();
        expect(find.text('日程 1'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-section-skeleton')),
          findsNothing,
        );
        await tester.pumpAndSettle();
        expect(find.text('日程 1'), findsOneWidget);
      },
    );

    testWidgets('lower schedule scroll does not resize the calendar', (
      tester,
    ) async {
      await _setScreen(tester, height: 640);
      final harness = await _pumpCalendar(tester, itemCount: 8);
      final item = find.byKey(ValueKey(calendarEvent(1).identityKey));
      final scrollable = Scrollable.of(tester.element(item));
      final beforeHeight = tester
          .getSize(find.byKey(const ValueKey('calendar-period-drag-surface')))
          .height;

      await tester.drag(item, const Offset(0, -180));
      await tester.pumpAndSettle();

      expect(scrollable.position.pixels, greaterThan(20));
      expect(harness.controller.state.viewMode, CalendarViewMode.week);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('calendar-period-drag-surface')))
            .height,
        beforeHeight,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('horizontal drag pages exactly one visible period', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);

      await tester.drag(
        find.byKey(const ValueKey('calendar-period-drag-surface')),
        const Offset(-190, 4),
      );
      await tester.pumpAndSettle();

      expect(
        CalendarDateMath.formatDate(harness.controller.state.selectedDate),
        '2026-09-07',
      );
    });

    testWidgets('month page follows the finger and previews muted next month', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-mode-button')));
      await tester.pumpAndSettle();

      final surface = find.byKey(
        const ValueKey('calendar-period-drag-surface'),
      );
      final surfaceRect = tester.getRect(surface);
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await gesture.moveBy(Offset(-surfaceRect.width * 0.12, 0));
      await tester.pump();
      await gesture.moveBy(Offset(-surfaceRect.width * 0.56, 0));
      await tester.pump();

      final currentRect = tester.getRect(
        find.byKey(const ValueKey('calendar-period-current')),
      );
      final nextRect = tester.getRect(
        find.byKey(const ValueKey('calendar-period-next')),
      );
      expect(
        currentRect.intersect(surfaceRect).isEmpty,
        isFalse,
        reason: 'surface=$surfaceRect current=$currentRect next=$nextRect',
      );
      expect(
        nextRect.intersect(surfaceRect).isEmpty,
        isFalse,
        reason: 'surface=$surfaceRect current=$currentRect next=$nextRect',
      );
      expect(
        tester
            .widget<Opacity>(
              find.byKey(const ValueKey('calendar-preview-next-date-opacity')),
            )
            .opacity,
        0.46,
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(harness.controller.state.anchorDate.month, 8);
      await tester.pumpAndSettle();

      expect(harness.controller.state.anchorDate.month, 9);
    });
  });

  group('CalendarPage frozen controls and return semantics', () {
    testWidgets('timeline and settings are separate accessible actions', (
      tester,
    ) async {
      await _setScreen(tester);
      await _pumpCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('calendar-timeline-button')));
      await tester.pump();
      expect(find.text('时间线视图暂未开放'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(CalendarPage)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-settings-button')));
      await tester.pump();
      expect(find.text('日历设置暂未开放'), findsOneWidget);
    });

    testWidgets('Today is contextual and month panel returns to exact today', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      expect(find.byKey(const ValueKey('calendar-today-button')), findsNothing);

      await harness.controller.navigatePeriod(1);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-today-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('calendar-year-month-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('calendar-month-panel-today')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('calendar-month-panel-today')),
      );
      await tester.pumpAndSettle();

      expect(harness.controller.state.selectedDate, DateTime.utc(2026, 8, 31));
      expect(find.byKey(const ValueKey('calendar-today-button')), findsNothing);
    });

    for (final target in ['event', 'habit', 'anniversary']) {
      for (final result in [false, true]) {
        testWidgets('$target detail changed=$result controls refresh', (
          tester,
        ) async {
          await _setScreen(tester);
          final harness = await _pumpCalendar(
            tester,
            onOpenEvent: (context, item) async =>
                target == 'event' ? result : false,
            onOpenHabit: (context, item) async =>
                target == 'habit' ? result : false,
            onOpenAnniversary: (context, item) async =>
                target == 'anniversary' ? result : false,
          );
          final before = harness.gateway.rangeRequests.length;
          final title = switch (target) {
            'event' => '日程 1',
            'habit' => '习惯 1',
            _ => '纪念日 1',
          };

          await tester.tap(find.text(title));
          await tester.pumpAndSettle();

          expect(
            harness.gateway.rangeRequests.length,
            result ? before + 1 : before,
          );
        });
      }
    }

    testWidgets('legacy ordinary detail return refreshes for correctness', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(
        tester,
        onOpenEvent: (context, item) async => null,
      );
      final before = harness.gateway.rangeRequests.length;

      await tester.tap(find.text('日程 1'));
      await tester.pumpAndSettle();

      expect(harness.gateway.rangeRequests.length, before + 1);
    });

    testWidgets('historical Habit creation receives today, not the past date', (
      tester,
    ) async {
      await _setScreen(tester);
      DateTime? received;
      final harness = await _pumpCalendar(
        tester,
        onCreateItem: (context, target, initialDate) async {
          if (target == CalendarCreateTarget.habit) received = initialDate;
          return false;
        },
      );
      await harness.controller.navigatePeriod(-1);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-create-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-create-habit')));
      await tester.pumpAndSettle();

      expect(received, DateTime.utc(2026, 8, 31));
    });

    for (final target in CalendarCreateTarget.values) {
      testWidgets('$target creation keeps future selection and refreshes', (
        tester,
      ) async {
        await _setScreen(tester);
        CalendarCreateTarget? receivedTarget;
        DateTime? receivedDate;
        final harness = await _pumpCalendar(
          tester,
          onCreateItem: (context, value, initialDate) async {
            receivedTarget = value;
            receivedDate = initialDate;
            return true;
          },
        );
        await harness.controller.navigatePeriod(1);
        await tester.pumpAndSettle();
        final before = harness.gateway.rangeRequests.length;

        await tester.tap(find.byKey(const ValueKey('calendar-create-fab')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(
              'calendar-create-${switch (target) {
                CalendarCreateTarget.event => 'event',
                CalendarCreateTarget.habit => 'habit',
                CalendarCreateTarget.anniversary => 'anniversary',
              }}',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(receivedTarget, target);
        expect(receivedDate, DateTime.utc(2026, 9, 7));
        expect(harness.controller.state.selectedDate, DateTime.utc(2026, 9, 7));
        expect(harness.gateway.rangeRequests.length, before + 1);
      });
    }

    testWidgets('adjacent-month date enters that date and month range', (
      tester,
    ) async {
      await _setScreen(tester);
      final harness = await _pumpCalendar(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-mode-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-31')));
      await tester.pumpAndSettle();

      expect(harness.controller.state.selectedDate, DateTime.utc(2026, 7, 31));
      expect(harness.controller.state.anchorDate.month, 7);
      expect(
        harness.controller.state.visibleRangeStart.weekday,
        DateTime.monday,
      );
    });

    testWidgets('empty and frozen status copy remains explicit', (
      tester,
    ) async {
      await _setScreen(tester);
      await _pumpCalendar(
        tester,
        onPage: (request) async =>
            calendarPageResponse(request: request, items: const []),
      );
      expect(find.text('空空如也的任务'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-empty-state')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-completed')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-event')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-habit')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('calendar-section-card-anniversary')),
        findsNothing,
      );

      await _pumpCalendar(
        tester,
        onPage: (request) async => calendarPageResponse(
          request: request,
          items: switch (request.section) {
            CalendarSection.event => [_continuingEvent()],
            CalendarSection.habit => _allHabitStatuses(request.date),
            CalendarSection.anniversary => const [],
          },
        ),
      );
      expect(find.text('进行中 · 进行中'), findsOneWidget);
      expect(find.text('未到日期'), findsWidgets);
      expect(find.text('待完成'), findsWidgets);
      expect(find.text('未完成'), findsWidgets);
      expect(find.text('进行中 · 0.5 / 1 页'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('calendar-section-toggle-completed')),
      );
      await tester.pumpAndSettle();
      expect(find.text('已完成 · 1 / 1 页'), findsOneWidget);
      expect(find.text('已跳过'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

class _CalendarHarness {
  const _CalendarHarness(this.controller, this.gateway);

  final CalendarController controller;
  final CallbackCalendarGateway gateway;
}

Future<_CalendarHarness> _pumpCalendar(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool disableAnimations = false,
  int itemCount = 1,
  CalendarOpenEvent? onOpenEvent,
  CalendarOpenHabit? onOpenHabit,
  CalendarOpenAnniversary? onOpenAnniversary,
  CalendarCreateItem? onCreateItem,
  CalendarRangeHandler? onRange,
  CalendarPageHandler? onPage,
}) async {
  final gateway = CallbackCalendarGateway(
    onRange: onRange,
    onPage:
        onPage ??
        (request) async => calendarPageResponse(
          request: request,
          items: calendarItemsFor(
            request.section,
            request.date,
            count: itemCount,
          ),
        ),
  );
  final controller = CalendarController(
    gateway: gateway,
    timezoneProvider: () async => calendarTimezone,
    nowProvider: () => DateTime(2026, 8, 31, 9),
  );
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF536DFE),
    brightness: brightness,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, colorScheme: scheme),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
          accessibleNavigation: disableAnimations,
        ),
        child: child!,
      ),
      home: CalendarPage(
        key: UniqueKey(),
        controller: controller,
        nowProvider: () => DateTime(2026, 8, 31, 9),
        disposeInjectedController: true,
        onOpenEvent: onOpenEvent,
        onOpenHabit: onOpenHabit ?? (context, item) async => false,
        onOpenAnniversary: onOpenAnniversary ?? (context, item) async => false,
        onCreateItem: onCreateItem,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _CalendarHarness(controller, gateway);
}

CalendarEventItemDto _continuingEvent() => CalendarEventItemDto(
  eventId: calendarUuid(99),
  title: '跨日会议',
  isAllDay: false,
  isRecurring: false,
  recurrenceRevision: null,
  occurrenceKey: null,
  occurrenceStartAt: null,
  occurrenceStartDate: null,
  startAt: DateTime.utc(2026, 8, 30, 12),
  endAt: DateTime.utc(2026, 9, 1, 12),
  startDate: null,
  endDate: null,
  dayDisplay: CalendarEventDayDisplay.continues,
  displayLocalTime: null,
  status: CalendarEventItemStatus.inProgress,
  hasActiveReminder: false,
);

CalendarEventItemDto _eventWithStatus(
  int index, {
  required String title,
  required CalendarEventItemStatus status,
}) => CalendarEventItemDto(
  eventId: calendarUuid(index),
  title: title,
  isAllDay: false,
  isRecurring: false,
  recurrenceRevision: null,
  occurrenceKey: null,
  occurrenceStartAt: null,
  occurrenceStartDate: null,
  startAt: DateTime.utc(2026, 8, 31, 1),
  endAt: DateTime.utc(2026, 8, 31, 2),
  startDate: null,
  endDate: null,
  dayDisplay: CalendarEventDayDisplay.startsAt,
  displayLocalTime: '09:00',
  status: status,
  hasActiveReminder: false,
);

List<CalendarHabitItemDto> _allHabitStatuses(String date) => [
  _habitWithStatus(1, date, CalendarHabitItemStatus.upcoming),
  _habitWithStatus(2, date, CalendarHabitItemStatus.absent),
  _habitWithStatus(3, date, CalendarHabitItemStatus.missed),
  _habitWithStatus(
    4,
    date,
    CalendarHabitItemStatus.partial,
    checkInId: calendarUuid(504),
    completed: 50,
    target: 100,
    unit: '页',
  ),
  _habitWithStatus(
    5,
    date,
    CalendarHabitItemStatus.done,
    checkInId: calendarUuid(505),
    completed: 100,
    target: 100,
    unit: '页',
  ),
  _habitWithStatus(
    6,
    date,
    CalendarHabitItemStatus.skipped,
    checkInId: calendarUuid(506),
  ),
];

CalendarHabitItemDto _habitWithStatus(
  int index,
  String date,
  CalendarHabitItemStatus status, {
  String? checkInId,
  int? completed,
  int? target,
  String? unit,
}) => CalendarHabitItemDto(
  habitId: calendarUuid(200 + index),
  date: date,
  title: '习惯状态 $index',
  status: status,
  checkInId: checkInId,
  completedCountHundredths: completed,
  targetCountHundredths: target,
  unit: unit,
  hasActiveReminder: false,
);

Future<void> _setScreen(
  WidgetTester tester, {
  double width = 360,
  double height = 800,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

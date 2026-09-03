import 'package:excellent_calendar/app/routing/app_router.dart';
import 'package:excellent_calendar/presentation/event_detail/models/event_detail_ui_state.dart';
import 'package:excellent_calendar/presentation/event_detail/pages/event_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('passes decoded event and occurrence ids to detail builder', (
    tester,
  ) async {
    EventDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name:
            '/event/detail/event%2F..%2Ftoday%3Fsource%3Dtap'
            '?occurrence_key=occurrence%2Fkey%3Fvalue%3D1%26next%3D%2Ftoday',
      ),
      todayBuilder: (_) => const Text('today'),
      eventDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('loaded event detail'));
      },
    );

    await _pushRoute(tester, route);

    expect(find.text('loaded event detail'), findsOneWidget);
    expect(received?.eventId, 'event/../today?source=tap');
    expect(received?.occurrenceKey, 'occurrence/key?value=1&next=/today');
  });

  testWidgets('event detail builder receives null for a series-only route', (
    tester,
  ) async {
    EventDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(name: '/event/detail/event-1'),
      todayBuilder: (_) => const Text('today'),
      eventDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('loaded event detail'));
      },
    );

    await _pushRoute(tester, route);

    expect(received?.eventId, 'event-1');
    expect(received?.occurrenceKey, isNull);
  });

  testWidgets('calendar event route preserves revision and timed anchor', (
    tester,
  ) async {
    EventDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name:
            '/event/detail/event-1?occurrence_key=occurrence-1'
            '&recurrence_revision=7'
            '&occurrence_start_at=2026-08-31T01%3A02%3A03Z',
      ),
      todayBuilder: (_) => const Text('today'),
      eventDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('calendar event detail'));
      },
    );

    await _pushRoute(tester, route);

    expect(received?.occurrenceKey, 'occurrence-1');
    expect(received?.recurrenceRevision, 7);
    expect(received?.occurrenceStartAt, DateTime.utc(2026, 8, 31, 1, 2, 3));
    expect(received?.occurrenceStartDate, isNull);
  });

  testWidgets('legacy EventDetailPageArguments remain supported', (
    tester,
  ) async {
    var builderCalled = false;
    final route = AppRouter.onGenerateRoute(
      RouteSettings(
        name: '/event/detail/event-1?occurrence_key=occurrence-1',
        arguments: EventDetailPageArguments(
          state: EventDetailUiState.preview(eventId: 'event-1'),
        ),
      ),
      todayBuilder: (_) => const Text('today'),
      eventDetailBuilder: (context, routeData) {
        builderCalled = true;
        return const Text('new builder');
      },
    );

    await _pushRoute(tester, route);

    expect(find.byType(EventDetailPage), findsOneWidget);
    expect(builderCalled, isFalse);
  });

  testWidgets('recovery summary and invalid external routes use today', (
    tester,
  ) async {
    final summaryRoute = AppRouter.onGenerateRoute(
      const RouteSettings(name: '/today'),
      todayBuilder: (_) => const Scaffold(body: Text('today')),
      eventDetailBuilder: (_, _) => const Text('detail'),
    );

    await _pushRoute(tester, summaryRoute);
    expect(find.text('today'), findsOneWidget);

    final externalRoute = AppRouter.onGenerateRoute(
      const RouteSettings(name: 'https://example.com/event/detail/event-1'),
      todayBuilder: (_) => const Scaffold(body: Text('safe today')),
      eventDetailBuilder: (_, _) => const Text('unsafe detail'),
    );

    await _pushRoute(tester, externalRoute);
    expect(find.text('safe today'), findsOneWidget);
    expect(find.text('unsafe detail'), findsNothing);
  });

  testWidgets('ambiguous occurrence query falls back to today', (tester) async {
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name:
            '/event/detail/event-1'
            '?occurrence_key=occurrence-1&occurrence_key=occurrence-2',
      ),
      todayBuilder: (_) => const Scaffold(body: Text('today fallback')),
      eventDetailBuilder: (_, _) => const Text('detail'),
    );

    await _pushRoute(tester, route);

    expect(find.text('today fallback'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('blank event or occurrence identity falls back to today', (
    tester,
  ) async {
    for (final name in [
      '/event/detail/%20',
      '/event/detail/event-1?occurrence_key=%20',
    ]) {
      final route = AppRouter.onGenerateRoute(
        RouteSettings(name: name),
        todayBuilder: (_) => const Scaffold(body: Text('blank fallback')),
        eventDetailBuilder: (_, _) => const Text('detail'),
      );

      await _pushRoute(tester, route);
      expect(find.text('blank fallback'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
    }
  });

  testWidgets('anniversary list route uses the configured feature builder', (
    tester,
  ) async {
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(name: '/anniversaries'),
      todayBuilder: (_) => const Text('today'),
      anniversaryListBuilder: (_) =>
          const Scaffold(body: Text('anniversary list')),
    );

    await _pushRoute(tester, route);

    expect(find.text('anniversary list'), findsOneWidget);
    expect(find.text('today'), findsNothing);
  });

  testWidgets('Habit detail route passes target and occurrence identity', (
    tester,
  ) async {
    HabitDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name: '/habit/detail/habit-1?occurrence_key=occurrence-1',
      ),
      todayBuilder: (_) => const Text('today'),
      habitDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('habit detail loaded'));
      },
    );

    await _pushRoute(tester, route);
    expect(find.text('habit detail loaded'), findsOneWidget);
    expect(received?.habitId, 'habit-1');
    expect(received?.occurrenceKey, 'occurrence-1');
  });

  testWidgets('calendar Habit route preserves selected natural date', (
    tester,
  ) async {
    HabitDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name: '/habit/detail/habit-1?selected_date=2026-08-31',
      ),
      todayBuilder: (_) => const Text('today'),
      habitDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('calendar habit detail'));
      },
    );

    await _pushRoute(tester, route);

    expect(received?.habitId, 'habit-1');
    expect(received?.selectedDate, '2026-08-31');
  });

  testWidgets('anniversary detail route passes the decoded id', (tester) async {
    AnniversaryDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name: '/anniversary/detail/promise%2F2026%3Fsource%3Dtap',
      ),
      todayBuilder: (_) => const Text('today'),
      anniversaryDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('anniversary detail loaded'));
      },
    );

    await _pushRoute(tester, route);

    expect(find.text('anniversary detail loaded'), findsOneWidget);
    expect(received?.anniversaryId, 'promise/2026?source=tap');
  });

  testWidgets('calendar Anniversary route preserves occurrence identity', (
    tester,
  ) async {
    AnniversaryDetailRouteData? received;
    final route = AppRouter.onGenerateRoute(
      const RouteSettings(
        name:
            '/anniversary/detail/anniversary-1'
            '?occurrence_key=occurrence-1&occurrence_date=2026-08-31',
      ),
      todayBuilder: (_) => const Text('today'),
      anniversaryDetailBuilder: (context, routeData) {
        received = routeData;
        return const Scaffold(body: Text('calendar anniversary detail'));
      },
    );

    await _pushRoute(tester, route);

    expect(received?.anniversaryId, 'anniversary-1');
    expect(received?.occurrenceKey, 'occurrence-1');
    expect(received?.occurrenceDate, '2026-08-31');
  });

  testWidgets('malformed calendar anchors fail safe to today', (tester) async {
    for (final name in [
      '/event/detail/event-1?recurrence_revision=0',
      '/event/detail/event-1?occurrence_start_at=2026-08-31T01%3A02%3A03.100Z',
      '/habit/detail/habit-1?selected_date=2026-02-30',
      '/anniversary/detail/anniversary-1?occurrence_key=occurrence-1',
      '/anniversary/detail/anniversary-1?occurrence_date=2026-08-31',
    ]) {
      final route = AppRouter.onGenerateRoute(
        RouteSettings(name: name),
        todayBuilder: (_) => const Scaffold(body: Text('calendar fallback')),
        eventDetailBuilder: (_, _) => const Text('event detail'),
        habitDetailBuilder: (_, _) => const Text('habit detail'),
        anniversaryDetailBuilder: (_, _) => const Text('anniversary detail'),
      );

      await _pushRoute(tester, route);
      expect(find.text('calendar fallback'), findsOneWidget);
    }
  });

  testWidgets('ring settings and active session use configured builders', (
    tester,
  ) async {
    for (final entry in <String, String>{
      '/settings/ring': 'ring settings page',
      '/ring/active': 'active ring page',
    }.entries) {
      final route = AppRouter.onGenerateRoute(
        RouteSettings(name: entry.key),
        todayBuilder: (_) => const Text('today'),
        ringSettingsBuilder: (_) =>
            const Scaffold(body: Text('ring settings page')),
        activeRingBuilder: (_) =>
            const Scaffold(body: Text('active ring page')),
      );

      await _pushRoute(tester, route);
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('today'), findsNothing);
    }
  });
}

Future<void> _pushRoute(WidgetTester tester, Route<dynamic> route) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(route),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

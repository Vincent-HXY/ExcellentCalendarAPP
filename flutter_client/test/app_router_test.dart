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

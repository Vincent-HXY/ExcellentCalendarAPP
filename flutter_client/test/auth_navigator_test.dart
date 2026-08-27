import 'package:excellent_calendar/app/routing/auth_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'goToProfile keeps the tab-shell root when profile is not a route',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final navigator = NavigatorAuthNavigator(navigatorKey);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          initialRoute: '/today',
          onGenerateInitialRoutes: (_) => <Route<dynamic>>[
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/today'),
              builder: (_) => const Scaffold(body: Text('profile-tab-shell')),
            ),
          ],
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => Scaffold(body: Text(settings.name!)),
          ),
        ),
      );
      navigatorKey.currentState!
        ..pushNamed('/account-security')
        ..pushNamed('/profile/email')
        ..pushNamed('/verification');
      await tester.pumpAndSettle();
      expect(find.text('/verification'), findsOneWidget);

      navigator.goToProfile();
      await tester.pumpAndSettle();

      expect(find.text('profile-tab-shell'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('goToProfile still returns to an explicit profile route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final navigator = NavigatorAuthNavigator(navigatorKey);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('today')),
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text(settings.name!)),
        ),
      ),
    );
    navigatorKey.currentState!
      ..pushNamed('/profile')
      ..pushNamed('/profile/email')
      ..pushNamed('/verification');
    await tester.pumpAndSettle();

    navigator.goToProfile();
    await tester.pumpAndSettle();

    expect(find.text('/profile'), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isTrue);
  });
}

import 'package:excellent_calendar/app/routing/app_router.dart';
import 'package:excellent_calendar/app/routing/auth_route_arguments.dart';
import 'package:excellent_calendar/application/auth/email_verification_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/backend_api_fixtures.dart';

void main() {
  WidgetBuilder pageBuilder(String label) =>
      (_) => Text(label);

  Route<dynamic> Function(RouteSettings) onGenerateRoute() =>
      (settings) => AppRouter.onGenerateRoute(
        settings,
        todayBuilder: pageBuilder('today'),
        authCheckBuilder: pageBuilder('auth-check'),
        loginBuilder: pageBuilder('login'),
        registerBuilder: pageBuilder('register'),
        verificationBuilder: pageBuilder('verification'),
        forgotPasswordBuilder: pageBuilder('forgot-password'),
        resetPasswordBuilder: pageBuilder('reset-password'),
        profileBuilder: pageBuilder('profile'),
        editProfileBuilder: pageBuilder('profile/edit'),
        changeEmailBuilder: pageBuilder('profile/email'),
        changePasswordBuilder: pageBuilder('profile/password'),
        accountSecurityBuilder: pageBuilder('account-security'),
      );

  MaterialApp app() => MaterialApp(onGenerateRoute: onGenerateRoute());

  testWidgets('every auth route resolves to its builder', (tester) async {
    const names = <String, String>{
      '/auth-check': 'auth-check',
      '/login': 'login',
      '/register': 'register',
      '/forgot-password': 'forgot-password',
      '/profile': 'profile',
      '/profile/edit': 'profile/edit',
      '/profile/email': 'profile/email',
      '/profile/password': 'profile/password',
      '/account-security': 'account-security',
    };
    await tester.pumpWidget(app());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    for (final entry in names.entries) {
      navigator.pushNamed(entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      navigator.pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('verification route requires typed arguments', (tester) async {
    await tester.pumpWidget(app());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(
      '/verification',
      arguments: VerificationPageArguments(
        challenge: challengeDto(),
        mode: EmailVerificationMode.registration,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('verification'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    navigator.pushNamed('/verification');
    await tester.pumpAndSettle();
    expect(
      find.text('login'),
      findsOneWidget,
      reason: 'missing arguments must fail safe to login',
    );
  });

  testWidgets('reset-password route requires typed arguments', (tester) async {
    await tester.pumpWidget(app());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed(
      '/reset-password',
      arguments: const ResetPasswordPageArguments(email: 'user@example.com'),
    );
    await tester.pumpAndSettle();
    expect(find.text('reset-password'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    navigator.pushNamed('/reset-password');
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
  });

  testWidgets('unknown routes still fall back to today', (tester) async {
    await tester.pumpWidget(app());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pushNamed('/unknown-path');
    await tester.pumpAndSettle();
    expect(find.text('today'), findsOneWidget);
  });
}

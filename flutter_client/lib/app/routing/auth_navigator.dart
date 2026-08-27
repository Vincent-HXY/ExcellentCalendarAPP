import 'package:flutter/material.dart';

import 'auth_route_arguments.dart';

/// Navigation surface for authentication flows. Pages depend on this
/// abstraction instead of the raw Navigator so tests can substitute it.
abstract interface class AuthNavigator {
  void goToLogin();

  void goToHome();

  void goToProfile();

  void goToVerification(VerificationPageArguments arguments);

  void push(String route);

  void pushResetPassword(ResetPasswordPageArguments arguments);

  void pop();
}

class NavigatorAuthNavigator implements AuthNavigator {
  const NavigatorAuthNavigator(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  NavigatorState? get _navigator => navigatorKey.currentState;

  @override
  void goToLogin() {
    _navigator?.pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  void goToHome() {
    _navigator?.pushNamedAndRemoveUntil('/today', (route) => false);
  }

  @override
  void goToProfile() {
    // Profile can either be an explicit route or the "My" tab hosted by the
    // first route. Never pop the root route when the tab-shell owns profile.
    _navigator?.popUntil(
      (route) => route.settings.name == '/profile' || route.isFirst,
    );
  }

  @override
  void goToVerification(VerificationPageArguments arguments) {
    _navigator?.pushNamed('/verification', arguments: arguments);
  }

  @override
  void push(String route) {
    _navigator?.pushNamed(route);
  }

  @override
  void pushResetPassword(ResetPasswordPageArguments arguments) {
    _navigator?.pushNamed('/reset-password', arguments: arguments);
  }

  @override
  void pop() {
    _navigator?.maybePop();
  }
}

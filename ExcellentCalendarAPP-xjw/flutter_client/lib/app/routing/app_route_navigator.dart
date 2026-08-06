import 'package:flutter/material.dart';

abstract interface class AppRouteNavigator {
  void go(String route);
}

class NavigatorAppRouteNavigator implements AppRouteNavigator {
  const NavigatorAppRouteNavigator(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  void go(String route) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    if (route == '/today') {
      navigator.pushNamedAndRemoveUntil(route, (candidate) => false);
      return;
    }
    navigator.pushNamed(route);
  }
}

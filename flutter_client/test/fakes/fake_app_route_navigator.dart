import 'package:excellent_calendar/app/routing/app_route_navigator.dart';

class FakeAppRouteNavigator implements AppRouteNavigator {
  final List<String> routes = [];

  @override
  void go(String route) {
    routes.add(route);
  }
}

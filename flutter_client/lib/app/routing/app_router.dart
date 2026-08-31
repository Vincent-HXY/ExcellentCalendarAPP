import 'package:flutter/material.dart';

import '../../presentation/event_detail/pages/event_detail_page.dart';
import 'auth_route_arguments.dart';

typedef EventDetailRouteBuilder =
    Widget Function(BuildContext context, EventDetailRouteData routeData);
typedef AnniversaryDetailRouteBuilder =
    Widget Function(BuildContext context, String anniversaryId);
typedef HabitDetailRouteBuilder =
    Widget Function(BuildContext context, HabitDetailRouteData routeData);

class HabitDetailRouteData {
  const HabitDetailRouteData({required this.habitId, this.occurrenceKey});
  final String habitId;
  final String? occurrenceKey;
}

class EventDetailRouteData {
  const EventDetailRouteData({
    required this.eventId,
    required this.occurrenceKey,
  });

  final String eventId;
  final String? occurrenceKey;
}

class AppRouter {
  const AppRouter._();

  /// Builds only the startup auth gate. Flutter's default initial-route
  /// generator also creates `/` for a deep initial route such as
  /// `/auth-check`, which would start the authenticated home underneath it.
  static List<Route<dynamic>> initialAuthCheckRoutes({
    required WidgetBuilder authCheckBuilder,
  }) => <Route<dynamic>>[
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/auth-check'),
      builder: authCheckBuilder,
    ),
  ];

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    required WidgetBuilder todayBuilder,
    EventDetailRouteBuilder? eventDetailBuilder,
    WidgetBuilder? anniversaryListBuilder,
    AnniversaryDetailRouteBuilder? anniversaryDetailBuilder,
    WidgetBuilder? habitListBuilder,
    WidgetBuilder? habitCreateBuilder,
    HabitDetailRouteBuilder? habitDetailBuilder,
    WidgetBuilder? appearanceBuilder,
    WidgetBuilder? ringSettingsBuilder,
    WidgetBuilder? activeRingBuilder,
    WidgetBuilder? authCheckBuilder,
    WidgetBuilder? loginBuilder,
    WidgetBuilder? registerBuilder,
    WidgetBuilder? verificationBuilder,
    WidgetBuilder? forgotPasswordBuilder,
    WidgetBuilder? resetPasswordBuilder,
    WidgetBuilder? profileBuilder,
    WidgetBuilder? editProfileBuilder,
    WidgetBuilder? changeEmailBuilder,
    WidgetBuilder? changePasswordBuilder,
    WidgetBuilder? accountSecurityBuilder,
  }) {
    final name = settings.name ?? '/today';
    if (name == '/today' || name == '/') {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/today'),
        builder: todayBuilder,
      );
    }
    if (name == '/anniversaries' && anniversaryListBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/anniversaries'),
        builder: anniversaryListBuilder,
      );
    }
    if (name == '/habits' && habitListBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/habits'),
        builder: habitListBuilder,
      );
    }
    if (name == '/habit/create' && habitCreateBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/habit/create'),
        builder: habitCreateBuilder,
      );
    }
    if (name == '/settings/appearance' && appearanceBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/settings/appearance'),
        builder: appearanceBuilder,
      );
    }
    if (name == '/settings/ring' && ringSettingsBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/settings/ring'),
        builder: ringSettingsBuilder,
      );
    }
    if (name == '/ring/active' && activeRingBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/ring/active'),
        builder: activeRingBuilder,
      );
    }
    final simpleRoute = _simpleAuthRoute(
      settings,
      name,
      authCheckBuilder: authCheckBuilder,
      loginBuilder: loginBuilder,
      registerBuilder: registerBuilder,
      forgotPasswordBuilder: forgotPasswordBuilder,
      profileBuilder: profileBuilder,
      editProfileBuilder: editProfileBuilder,
      changeEmailBuilder: changeEmailBuilder,
      changePasswordBuilder: changePasswordBuilder,
      accountSecurityBuilder: accountSecurityBuilder,
    );
    if (simpleRoute != null) {
      return simpleRoute;
    }
    if (name == '/verification' && verificationBuilder != null) {
      final arguments = settings.arguments;
      if (arguments is VerificationPageArguments) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: verificationBuilder,
        );
      }
      // Missing/invalid arguments are a programming error; fail safe to login.
      return _namedRoute(settings, '/login', loginBuilder ?? todayBuilder);
    }
    if (name == '/reset-password' && resetPasswordBuilder != null) {
      final arguments = settings.arguments;
      if (arguments is ResetPasswordPageArguments) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: resetPasswordBuilder,
        );
      }
      return _namedRoute(settings, '/login', loginBuilder ?? todayBuilder);
    }

    final parsedUri = Uri.tryParse(name);
    final uri =
        parsedUri == null ||
            parsedUri.hasScheme ||
            parsedUri.hasAuthority ||
            parsedUri.hasFragment
        ? null
        : parsedUri;
    final segments = uri?.pathSegments ?? const <String>[];
    if (uri != null && segments.length == 3 && segments[1] == 'detail') {
      final type = segments[0];
      final id = segments[2];
      if ({'event', 'habit', 'anniversary'}.contains(type) &&
          id.trim().isNotEmpty) {
        if (type == 'event') {
          final occurrenceValues = uri.queryParametersAll['occurrence_key'];
          if (occurrenceValues != null &&
              (occurrenceValues.length != 1 ||
                  occurrenceValues.single.trim().isEmpty)) {
            return _todayRoute(todayBuilder);
          }
          final occurrenceKey = occurrenceValues?.single;
          final arguments = settings.arguments;
          if (arguments is EventDetailPageArguments) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => EventDetailPage(
                state: arguments.state,
                onMore: arguments.onMore,
                onEdit: arguments.onEdit,
                onComplete: arguments.onComplete,
                onEditField: arguments.onEditField,
                canComplete: arguments.canComplete,
              ),
            );
          }
          if (eventDetailBuilder != null) {
            final routeData = EventDetailRouteData(
              eventId: id,
              occurrenceKey: occurrenceKey,
            );
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => eventDetailBuilder(context, routeData),
            );
          }
        }
        if (type == 'anniversary' && anniversaryDetailBuilder != null) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => anniversaryDetailBuilder(context, id),
          );
        }
        if (type == 'habit' && habitDetailBuilder != null) {
          final occurrenceValues = uri.queryParametersAll['occurrence_key'];
          if (occurrenceValues != null &&
              (occurrenceValues.length != 1 ||
                  occurrenceValues.single.trim().isEmpty)) {
            return _todayRoute(todayBuilder);
          }
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => habitDetailBuilder(
              context,
              HabitDetailRouteData(
                habitId: id,
                occurrenceKey: occurrenceValues?.single,
              ),
            ),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              NotificationTargetDetailPage(targetType: type, targetId: id),
        );
      }
    }

    return _todayRoute(todayBuilder);
  }

  static MaterialPageRoute<void>? _simpleAuthRoute(
    RouteSettings settings,
    String name, {
    WidgetBuilder? authCheckBuilder,
    WidgetBuilder? loginBuilder,
    WidgetBuilder? registerBuilder,
    WidgetBuilder? forgotPasswordBuilder,
    WidgetBuilder? profileBuilder,
    WidgetBuilder? editProfileBuilder,
    WidgetBuilder? changeEmailBuilder,
    WidgetBuilder? changePasswordBuilder,
    WidgetBuilder? accountSecurityBuilder,
  }) {
    final builders = <String, WidgetBuilder?>{
      '/auth-check': authCheckBuilder,
      '/login': loginBuilder,
      '/register': registerBuilder,
      '/forgot-password': forgotPasswordBuilder,
      '/profile': profileBuilder,
      '/profile/edit': editProfileBuilder,
      '/profile/email': changeEmailBuilder,
      '/profile/password': changePasswordBuilder,
      '/account-security': accountSecurityBuilder,
    };
    final builder = builders[name];
    if (builder == null) {
      return null;
    }
    return _namedRoute(settings, name, builder);
  }

  static MaterialPageRoute<void> _namedRoute(
    RouteSettings settings,
    String name,
    WidgetBuilder builder,
  ) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name, arguments: settings.arguments),
    builder: builder,
  );

  static MaterialPageRoute<void> _todayRoute(WidgetBuilder todayBuilder) =>
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/today'),
        builder: todayBuilder,
      );
}

class NotificationTargetDetailPage extends StatelessWidget {
  const NotificationTargetDetailPage({
    required this.targetType,
    required this.targetId,
    super.key,
  });

  final String targetType;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    final title = switch (targetType) {
      'event' => '日程详情',
      'habit' => '习惯详情',
      'anniversary' => '纪念日详情',
      _ => '详情',
    };
    final missingMessage = switch (targetType) {
      'event' => '该日程不存在或已删除',
      'habit' => '该习惯不存在或已删除',
      'anniversary' => '该纪念日不存在或已删除',
      _ => '该内容不存在或已删除',
    };

    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_busy_rounded,
                        size: 42,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        missingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ID: $targetId',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/routing/app_route_navigator.dart';
import 'app/routing/app_router.dart';
import 'app/routing/notification_tap_router.dart';
import 'application/event/create_event_use_case.dart';
import 'application/event/complete_event_use_case.dart';
import 'application/event/read_events_use_case.dart';
import 'application/reminder/schedule_pending_reminders_use_case.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/inbox/inbox_page.dart';

void main() {
  runApp(const ExcellentCalendarApp());
}

class ExcellentCalendarApp extends StatefulWidget {
  const ExcellentCalendarApp({super.key});

  @override
  State<ExcellentCalendarApp> createState() => _ExcellentCalendarAppState();
}

class _ExcellentCalendarAppState extends State<ExcellentCalendarApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final MethodChannelEventAdapter _eventGateway;
  late final SchedulePendingRemindersUseCase _schedulePendingRemindersUseCase;
  late final CreateEventUseCase _createEventUseCase;
  late final AppNotificationBootstrap _notificationBootstrap;

  @override
  void initState() {
    super.initState();
    _eventGateway = MethodChannelEventAdapter();
    final reminderGateway = MethodChannelReminderAdapter();
    _schedulePendingRemindersUseCase = SchedulePendingRemindersUseCase(
      reminderGateway,
    );
    _createEventUseCase = CreateEventUseCase(
      _eventGateway,
      schedulePendingRemindersUseCase: _schedulePendingRemindersUseCase,
    );
    _notificationBootstrap = AppNotificationBootstrap(
      notificationGateway: MethodChannelNotificationAdapter(),
      schedulePendingRemindersUseCase: _schedulePendingRemindersUseCase,
      notificationTapRouter: NotificationTapRouter(
        navigator: NavigatorAppRouteNavigator(_navigatorKey),
      ),
    );
  }

  Widget _buildToday(BuildContext context) {
    return AppNotificationHost(
      bootstrap: _notificationBootstrap,
      child: InboxPage(
        readEventsUseCase: ReadEventsUseCase(_eventGateway),
        createEventUseCase: _createEventUseCase,
        completeEventUseCase: CompleteEventUseCase(_eventGateway),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Excellent Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38B9C5)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      initialRoute: '/today',
      onGenerateRoute: (settings) =>
          AppRouter.onGenerateRoute(settings, todayBuilder: _buildToday),
    );
  }

  @override
  void dispose() {
    _notificationBootstrap.dispose();
    super.dispose();
  }
}

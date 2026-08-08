import 'package:flutter/material.dart';

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/routing/app_route_navigator.dart';
import 'app/routing/app_router.dart';
import 'app/routing/notification_tap_router.dart';
import 'application/event/create_event_use_case.dart';
import 'application/event/complete_event_use_case.dart';
import 'application/event/read_events_use_case.dart';
import 'application/event/recurring_event_detail_controller.dart';
import 'application/event/update_event_use_case.dart';
import 'application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'application/timezone/timezone_application_service.dart';
import 'application/anniversary/app_clock.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'data/anniversary/fake_anniversary_gateway.dart';
import 'data/anniversary/fake_anniversary_share_gateway.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/anniversary/pages/anniversary_detail_page.dart';
import 'presentation/anniversary/pages/anniversary_list_page.dart';
import 'presentation/event_detail/pages/event_detail_flow_page.dart';
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
  late final ReconcileReminderScheduleUseCase _reconcileReminderScheduleUseCase;
  late final CreateEventUseCase _createEventUseCase;
  late final CompleteEventUseCase _completeEventUseCase;
  late final UpdateEventUseCase _updateEventUseCase;
  late final TimezoneApplicationService _timezoneService;
  late final AppNotificationBootstrap _notificationBootstrap;
  late final AppClock _anniversaryClock;
  late final FakeAnniversaryGateway _anniversaryGateway;
  late final FakeAnniversaryShareGateway _anniversaryShareGateway;

  @override
  void initState() {
    super.initState();
    _eventGateway = MethodChannelEventAdapter();
    _anniversaryClock = FixedAppClock(DateTime(2026, 8, 6));
    _anniversaryGateway = FakeAnniversaryGateway(clock: _anniversaryClock);
    _anniversaryShareGateway = FakeAnniversaryShareGateway();
    _timezoneService = TimezoneApplicationService(
      MethodChannelTimezoneAdapter(),
    );
    final reminderGateway = MethodChannelReminderAdapter();
    _reconcileReminderScheduleUseCase = ReconcileReminderScheduleUseCase(
      reminderGateway,
    );
    _createEventUseCase = CreateEventUseCase(
      _eventGateway,
      reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
    );
    _completeEventUseCase = CompleteEventUseCase(
      _eventGateway,
      reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
    );
    _updateEventUseCase = UpdateEventUseCase(
      _eventGateway,
      reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
    );
    _notificationBootstrap = AppNotificationBootstrap(
      notificationGateway: MethodChannelNotificationAdapter(),
      reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
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
        completeEventUseCase: _completeEventUseCase,
        timezoneService: _timezoneService,
        onOpenAnniversaries: () =>
            Navigator.of(context).pushNamed('/anniversaries'),
      ),
    );
  }

  Widget _buildAnniversaryList(BuildContext context) {
    return AnniversaryListPage(
      gateway: _anniversaryGateway,
      shareGateway: _anniversaryShareGateway,
      clock: _anniversaryClock,
    );
  }

  Widget _buildAnniversaryDetail(BuildContext context, String anniversaryId) {
    return AnniversaryDetailPage(
      anniversaryId: anniversaryId,
      gateway: _anniversaryGateway,
      shareGateway: _anniversaryShareGateway,
      clock: _anniversaryClock,
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
      onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
        settings,
        todayBuilder: _buildToday,
        anniversaryListBuilder: _buildAnniversaryList,
        anniversaryDetailBuilder: _buildAnniversaryDetail,
        eventDetailBuilder: (context, routeData) => EventDetailFlowPage(
          controller: RecurringEventDetailController(
            eventId: routeData.eventId,
            gateway: _eventGateway,
            timezoneService: _timezoneService,
            reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
            focusOccurrenceKey: routeData.occurrenceKey,
          ),
          completeEventUseCase: _completeEventUseCase,
          updateEventUseCase: _updateEventUseCase,
          timezoneService: _timezoneService,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notificationBootstrap.dispose();
    super.dispose();
  }
}

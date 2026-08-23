import 'package:flutter/material.dart';

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/bootstrap/category_repository_composition.dart';
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
import 'boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_ring_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'data/anniversary/fake_anniversary_share_gateway.dart';
import 'data/anniversary/native_anniversary_gateway.dart';
import 'gateway_interfaces/anniversary_gateway.dart';
import 'gateway_interfaces/category_repository.dart';
import 'gateway_interfaces/ring_native_gateway.dart';
import 'application/ring/active_ring_session_controller.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/anniversary/pages/anniversary_detail_page.dart';
import 'presentation/anniversary/pages/anniversary_list_page.dart';
import 'presentation/event_detail/pages/event_detail_flow_page.dart';
import 'presentation/inbox/inbox_page.dart';
import 'presentation/ring/active_ring_session_page.dart';
import 'presentation/ring/ring_session_host.dart';
import 'presentation/ring/ring_settings_page.dart';

void main() {
  runApp(buildProductionApp());
}

ExcellentCalendarApp buildProductionApp() {
  return ExcellentCalendarApp(
    anniversaryClock: const SystemAppClock(),
    categoryRepository: buildProductionCategoryRepository(),
    ringGateway: MethodChannelRingAdapter(),
  );
}

class ExcellentCalendarApp extends StatefulWidget {
  const ExcellentCalendarApp({
    required this.anniversaryClock,
    required this.categoryRepository,
    required this.ringGateway,
    super.key,
  });

  final AppClock anniversaryClock;
  final CategoryRepository categoryRepository;
  final RingNativeGateway ringGateway;

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
  late final AnniversaryGateway _anniversaryGateway;
  late final FakeAnniversaryShareGateway _anniversaryShareGateway;
  late final CategoryRepository _categoryRepository;
  late final RingNativeGateway _ringGateway;
  late final ActiveRingSessionController _activeRingController;

  @override
  void initState() {
    super.initState();
    _eventGateway = MethodChannelEventAdapter();
    _ringGateway = widget.ringGateway;
    _activeRingController = ActiveRingSessionController(
      ringGateway: _ringGateway,
      eventGateway: _eventGateway,
    );
    _anniversaryClock = widget.anniversaryClock;
    _anniversaryShareGateway = FakeAnniversaryShareGateway();
    _categoryRepository = widget.categoryRepository;
    final timezoneGateway = MethodChannelTimezoneAdapter();
    _timezoneService = TimezoneApplicationService(timezoneGateway);
    _anniversaryGateway = NativeAnniversaryGateway(
      nativeGateway: MethodChannelAnniversaryAdapter(),
      timezoneGateway: timezoneGateway,
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
        categoryRepository: _categoryRepository,
        onOpenAnniversaries: () =>
            Navigator.of(context).pushNamed('/anniversaries'),
        onOpenRingSettings: () =>
            Navigator.of(context).pushNamed('/settings/ring'),
        ringGateway: _ringGateway,
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
    return RingSessionHost(
      controller: _activeRingController,
      navigatorKey: _navigatorKey,
      child: MaterialApp(
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
          ringSettingsBuilder: (_) => RingSettingsPage(gateway: _ringGateway),
          activeRingBuilder: (_) =>
              ActiveRingSessionPage(controller: _activeRingController),
          eventDetailBuilder: (context, routeData) => EventDetailFlowPage(
            controller: RecurringEventDetailController(
              eventId: routeData.eventId,
              gateway: _eventGateway,
              timezoneService: _timezoneService,
              reconcileReminderScheduleUseCase:
                  _reconcileReminderScheduleUseCase,
              focusOccurrenceKey: routeData.occurrenceKey,
            ),
            completeEventUseCase: _completeEventUseCase,
            updateEventUseCase: _updateEventUseCase,
            timezoneService: _timezoneService,
            categoryRepository: _categoryRepository,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _activeRingController.dispose();
    _notificationBootstrap.dispose();
    super.dispose();
  }
}

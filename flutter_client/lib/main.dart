import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/bootstrap/category_repository_composition.dart';
import 'app/bootstrap/notification_permission_controller.dart';
import 'app/localization/app_localization.dart';
import 'app/routing/app_route_navigator.dart';
import 'app/routing/app_router.dart';
import 'app/routing/auth_navigator.dart';
import 'app/routing/notification_tap_router.dart';
import 'application/anniversary/app_clock.dart';
import 'application/appearance/appearance_controller.dart';
import 'application/calendar/calendar_controller.dart';
import 'application/calendar/calendar_creation_policy.dart';
import 'application/auth/auth_service.dart';
import 'application/auth/auth_session_controller.dart';
import 'application/auth/logout_service.dart';
import 'application/auth/startup_auth_check_use_case.dart';
import 'application/auth/token_refresh_coordinator.dart';
import 'application/event/complete_event_use_case.dart';
import 'application/event/create_event_use_case.dart';
import 'application/event/read_events_use_case.dart';
import 'application/event/recurring_event_detail_controller.dart';
import 'application/event/update_event_use_case.dart';
import 'application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'application/search/search_controller.dart';
import 'application/timezone/timezone_application_service.dart';
import 'boundary_adapters/backend_api/backend_api_config.dart';
import 'boundary_adapters/backend_api/dio_backend_api_client.dart';
import 'boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_appearance_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_calendar_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_habit_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_ring_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_search_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'data/anniversary/fake_anniversary_share_gateway.dart';
import 'data/anniversary/native_anniversary_gateway.dart';
import 'data/auth/dio_auth_gateway.dart';
import 'boundary_adapters/dart_method_channel/method_channel_refresh_token_secure_store.dart';
import 'data/user/dio_user_gateway.dart';
import 'data/user/user_profile_file_cache.dart';
import 'gateway_interfaces/anniversary_gateway.dart';
import 'gateway_interfaces/appearance_preferences_gateway.dart';
import 'gateway_interfaces/calendar_gateway.dart';
import 'gateway_interfaces/category_repository.dart';
import 'gateway_interfaces/habit_gateway.dart';
import 'gateway_interfaces/ring_native_gateway.dart';
import 'gateway_interfaces/search_gateway.dart';
import 'gateway_interfaces/search_history_gateway.dart';
import 'application/ring/active_ring_session_controller.dart';
import 'gateway_interfaces/refresh_token_secure_store_gateway.dart';
import 'native_contract/calendar/calendar_response_dtos.dart';
import 'native_contract/user/current_user_response_dto.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/anniversary/pages/anniversary_detail_page.dart';
import 'presentation/anniversary/pages/anniversary_list_page.dart';
import 'presentation/anniversary/pages/create_anniversary_page.dart';
import 'presentation/appearance/appearance_page.dart';
import 'presentation/auth/pages/auth_check_page.dart';
import 'presentation/auth/pages/email_verification_page.dart';
import 'presentation/auth/pages/forgot_password_page.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/auth/pages/register_page.dart';
import 'presentation/auth/pages/reset_password_page.dart';
import 'presentation/calendar/calendar_page.dart';
import 'presentation/event_detail/pages/event_detail_flow_page.dart';
import 'presentation/home/main_tab_page.dart';
import 'presentation/habit/habit_design.dart';
import 'presentation/habit/pages/habit_detail_page.dart';
import 'presentation/habit/pages/habit_form_page.dart';
import 'presentation/habit/pages/habit_list_page.dart';
import 'presentation/inbox/inbox_page.dart';
import 'presentation/new_schedule/new_schedule_page.dart';
import 'presentation/ring/active_ring_session_page.dart';
import 'presentation/ring/ring_session_host.dart';
import 'presentation/ring/ring_settings_page.dart';
import 'presentation/search/pages/search_page.dart';
import 'presentation/profile/pages/account_security_page.dart';
import 'presentation/profile/pages/change_email_page.dart';
import 'presentation/profile/pages/change_password_page.dart';
import 'presentation/profile/pages/edit_profile_page.dart';
import 'presentation/profile/pages/profile_page.dart';

void main() {
  runApp(buildProductionApp());
}

ExcellentCalendarApp buildProductionApp() {
  return ExcellentCalendarApp(
    anniversaryClock: const SystemAppClock(),
    categoryRepository: buildProductionCategoryRepository(),
    ringGateway: MethodChannelRingAdapter(),
    habitGateway: MethodChannelHabitAdapter(),
    appearanceGateway: MethodChannelAppearanceAdapter(),
    calendarGateway: MethodChannelCalendarAdapter(),
  );
}

/// Production auth wiring built at composition time. Test hosts can inject
/// their own fakes through ExcellentCalendarApp.authDependencies.
AuthDependencies buildAuthDependencies({
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  final navigator = NavigatorAuthNavigator(navigatorKey);
  final session = AuthSessionController();
  final secureStore = MethodChannelRefreshTokenSecureStore();
  late final TokenRefreshCoordinator refreshCoordinator;
  final client = DioBackendApiClient(
    config: const BackendApiConfig(),
    accessTokenProvider: () => session.accessToken,
    refreshSession: () => refreshCoordinator.refreshSession(),
    onSessionEnded: () => refreshCoordinator.endSession(),
  );
  final authGateway = DioAuthGateway(client);
  final userGateway = DioUserGateway(client);
  final profileCache = UserProfileFileCache();
  final authService = AuthService(
    authGateway: authGateway,
    userGateway: userGateway,
    secureStore: secureStore,
    session: session,
    profileCache: profileCache,
  );
  refreshCoordinator = TokenRefreshCoordinator(
    authGateway: authGateway,
    secureStore: secureStore,
    session: session,
    onSessionEnded: navigator.goToLogin,
  );
  final startupCheck = StartupAuthCheckUseCase(
    secureStore: secureStore,
    refreshCoordinator: refreshCoordinator,
    session: session,
    authService: authService,
  );
  final logoutService = LogoutService(
    authGateway: authGateway,
    secureStore: secureStore,
    authService: authService,
  );
  return AuthDependencies(
    session: session,
    authService: authService,
    secureStore: secureStore,
    startupCheck: startupCheck,
    logoutService: logoutService,
    navigator: navigator,
    profileCache: profileCache,
  );
}

/// Bundle of production auth objects handed to ExcellentCalendarApp.
class AuthDependencies {
  const AuthDependencies({
    required this.session,
    required this.authService,
    required this.secureStore,
    required this.startupCheck,
    required this.logoutService,
    required this.navigator,
    required this.profileCache,
  });

  final AuthSessionController session;
  final AuthService authService;
  final RefreshTokenSecureStoreGateway secureStore;
  final StartupAuthCheckUseCase startupCheck;
  final LogoutService logoutService;
  final AuthNavigator navigator;
  final UserProfileCacheStore profileCache;
}

class ExcellentCalendarApp extends StatefulWidget {
  const ExcellentCalendarApp({
    required this.anniversaryClock,
    required this.categoryRepository,
    required this.ringGateway,
    required this.habitGateway,
    required this.appearanceGateway,
    this.calendarGateway,
    this.searchGateway,
    this.searchHistoryGateway,
    this.authDependencies,
    this.initialRoute = '/auth-check',
    super.key,
  });

  final AppClock anniversaryClock;
  final CategoryRepository categoryRepository;
  final RingNativeGateway ringGateway;
  final HabitGateway habitGateway;
  final AppearancePreferencesGateway appearanceGateway;
  final CalendarGateway? calendarGateway;
  final SearchGateway? searchGateway;
  final SearchHistoryGateway? searchHistoryGateway;
  final AuthDependencies? authDependencies;
  final String initialRoute;

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
  late final NotificationPermissionController _notificationPermissionController;
  late final AppClock _anniversaryClock;
  late final AnniversaryGateway _anniversaryGateway;
  late final FakeAnniversaryShareGateway _anniversaryShareGateway;
  late final CategoryRepository _categoryRepository;
  late final RingNativeGateway _ringGateway;
  late final HabitGateway _habitGateway;
  late final AppearanceController _appearanceController;
  late final CalendarController _calendarController;
  late final SearchController _searchController;
  late final ActiveRingSessionController _activeRingController;
  late final MethodChannelTimezoneAdapter _timezoneGateway;
  late final AuthDependencies _authDeps;
  bool _ownsAuthDeps = false;
  late Future<String> _habitTimezoneFuture;

  @override
  void initState() {
    super.initState();
    _eventGateway = MethodChannelEventAdapter();
    _ringGateway = widget.ringGateway;
    _habitGateway = widget.habitGateway;
    _appearanceController = AppearanceController(widget.appearanceGateway);
    _appearanceController.initialize();
    _activeRingController = ActiveRingSessionController(
      ringGateway: _ringGateway,
      eventGateway: _eventGateway,
    );
    _anniversaryClock = widget.anniversaryClock;
    _anniversaryShareGateway = FakeAnniversaryShareGateway();
    _categoryRepository = widget.categoryRepository;
    _timezoneGateway = MethodChannelTimezoneAdapter();
    _calendarController = CalendarController(
      gateway: widget.calendarGateway ?? MethodChannelCalendarAdapter(),
      timezoneProvider: _resolveHabitTimezone,
    );
    final searchAdapter = MethodChannelSearchAdapter();
    _searchController = SearchController(
      gateway: widget.searchGateway ?? searchAdapter,
      historyGateway: widget.searchHistoryGateway ?? searchAdapter,
      timezoneProvider: _resolveHabitTimezone,
      categoryRepository: _categoryRepository,
    );
    final timezoneGateway = _timezoneGateway;
    _habitTimezoneFuture = _resolveHabitTimezone();
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
    final notificationGateway = MethodChannelNotificationAdapter();
    _notificationPermissionController = NotificationPermissionController(
      notificationGateway,
    );
    _notificationBootstrap = AppNotificationBootstrap(
      notificationGateway: notificationGateway,
      reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
      notificationTapRouter: NotificationTapRouter(
        navigator: NavigatorAppRouteNavigator(_navigatorKey),
      ),
    );
    final injected = widget.authDependencies;
    if (injected == null) {
      _authDeps = buildAuthDependencies(navigatorKey: _navigatorKey);
      _ownsAuthDeps = true;
    } else {
      _authDeps = injected;
    }
  }

  String _localeTag() {
    return WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag();
  }

  Future<String> _deviceTimezone() async {
    final invocation = await _timezoneGateway.getDeviceTimezone();
    if (invocation.result.ok && invocation.result.data != null) {
      return invocation.result.data!.timezone;
    }
    return '';
  }

  Widget _buildToday(BuildContext context) {
    return MainTabPage(
      scheduleBuilder: (tabContext) => AppNotificationHost(
        bootstrap: _notificationBootstrap,
        child: InboxPage(
          readEventsUseCase: ReadEventsUseCase(_eventGateway),
          createEventUseCase: _createEventUseCase,
          completeEventUseCase: _completeEventUseCase,
          timezoneService: _timezoneService,
          categoryRepository: _categoryRepository,
          onOpenAnniversaries: () =>
              Navigator.of(tabContext).pushNamed('/anniversaries'),
          onOpenHabits: () => Navigator.of(tabContext).pushNamed('/habits'),
          ringGateway: _ringGateway,
        ),
      ),
      calendarBuilder: (_) => CalendarPage(
        controller: _calendarController,
        onOpenEvent: (routeContext, item) =>
            _openCalendarDetail(routeContext, _calendarEventRoute(item)),
        onOpenHabit: (routeContext, item) =>
            _openCalendarDetail(routeContext, _calendarHabitRoute(item)),
        onOpenAnniversary: (routeContext, item) =>
            _openCalendarDetail(routeContext, _calendarAnniversaryRoute(item)),
        onCreateItem: _createCalendarItem,
      ),
      searchBuilder: (_) => SearchPage(
        controller: _searchController,
        externallyManagedTabActivity: true,
      ),
      onTabChanged: (index) {
        unawaited(_calendarController.setActive(index == 1));
        unawaited(_searchController.setActive(index == 2));
      },
      profileBuilder: (_) => ProfilePage(
        authService: _authDeps.authService,
        session: _authDeps.session,
        navigator: _authDeps.navigator,
        showBack: false,
        onOpenAppearance: () =>
            Navigator.of(context).pushNamed('/settings/appearance'),
      ),
    );
  }

  String _calendarEventRoute(CalendarEventItemDto item) {
    final query = <String, String>{
      if (item.occurrenceKey != null) 'occurrence_key': item.occurrenceKey!,
      if (item.recurrenceRevision != null)
        'recurrence_revision': '${item.recurrenceRevision}',
      if (item.occurrenceStartAt != null)
        'occurrence_start_at': _formatWholeSecondUtc(item.occurrenceStartAt!),
      if (item.occurrenceStartDate != null)
        'occurrence_start_date': item.occurrenceStartDate!,
    };
    return _detailRoute('event', item.eventId, query);
  }

  Future<bool?> _openCalendarDetail(BuildContext context, String route) async {
    final result = await Navigator.of(context).pushNamed<Object?>(route);
    return switch (result) {
      ContentDetailRouteOutcome.changed ||
      ContentDetailRouteOutcome.deleted ||
      true => true,
      _ => false,
    };
  }

  String _calendarHabitRoute(CalendarHabitItemDto item) =>
      _detailRoute('habit', item.habitId, {'selected_date': item.date});

  String _calendarAnniversaryRoute(CalendarAnniversaryItemDto item) =>
      _detailRoute('anniversary', item.anniversaryId, {
        'occurrence_key': item.occurrenceKey,
        'occurrence_date': item.occurrenceDate,
      });

  String _detailRoute(String type, String id, Map<String, String> query) {
    final encodedQuery = Uri(queryParameters: query).query;
    final base = '/$type/detail/${Uri.encodeComponent(id)}';
    return encodedQuery.isEmpty ? base : '$base?$encodedQuery';
  }

  String _formatWholeSecondUtc(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  Future<bool?> _createCalendarItem(
    BuildContext context,
    CalendarCreateTarget target,
    DateTime initialDate,
  ) async {
    switch (target) {
      case CalendarCreateTarget.event:
        return Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => NewSchedulePage(
              createUseCase: _createEventUseCase,
              timezoneService: _timezoneService,
              categoryRepository: _categoryRepository,
              ringGateway: _ringGateway,
              initialDate: initialDate,
            ),
          ),
        );
      case CalendarCreateTarget.habit:
        final timezone = await _resolveHabitTimezone();
        if (!context.mounted) return false;
        return Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => HabitFormPage(
              gateway: _habitGateway,
              timezoneProvider: () => timezone,
              categoryRepository: _categoryRepository,
              permissionController: _notificationPermissionController,
              initialStartDate: CalendarCreationPolicy.habitInitialDate(
                selectedDate: initialDate,
                now: DateTime.now(),
              ),
            ),
          ),
        );
      case CalendarCreateTarget.anniversary:
        final result = await Navigator.of(context).push<Object?>(
          MaterialPageRoute<Object?>(
            builder: (_) => CreateAnniversaryPage(
              gateway: _anniversaryGateway,
              clock: _anniversaryClock,
              initialDate: initialDate,
              permissionController: _notificationPermissionController,
            ),
          ),
        );
        return result != null;
    }
  }

  Widget _buildAnniversaryList(BuildContext context) {
    return AnniversaryListPage(
      gateway: _anniversaryGateway,
      shareGateway: _anniversaryShareGateway,
      clock: _anniversaryClock,
      permissionController: _notificationPermissionController,
    );
  }

  Widget _buildAnniversaryDetail(
    BuildContext context,
    AnniversaryDetailRouteData routeData,
  ) {
    return AnniversaryDetailPage(
      anniversaryId: routeData.anniversaryId,
      focusOccurrenceKey: routeData.occurrenceKey,
      focusOccurrenceDate: routeData.occurrenceDate,
      gateway: _anniversaryGateway,
      shareGateway: _anniversaryShareGateway,
      clock: _anniversaryClock,
      permissionController: _notificationPermissionController,
    );
  }

  Widget _buildHabitList(BuildContext context) => _withHabitTimezone(
    (timezone) =>
        HabitListPage(gateway: _habitGateway, timezoneProvider: () => timezone),
  );

  Widget _buildHabitCreate(BuildContext context) => _withHabitTimezone(
    (timezone) => HabitFormPage(
      gateway: _habitGateway,
      timezoneProvider: () => timezone,
      categoryRepository: _categoryRepository,
      permissionController: _notificationPermissionController,
    ),
  );

  Widget _buildHabitDetail(
    BuildContext context,
    HabitDetailRouteData routeData,
  ) => _withHabitTimezone(
    (timezone) => HabitDetailPage(
      habitId: routeData.habitId,
      focusOccurrenceKey: routeData.occurrenceKey,
      focusDate: routeData.selectedDate,
      gateway: _habitGateway,
      timezoneProvider: () => timezone,
      categoryRepository: _categoryRepository,
      permissionController: _notificationPermissionController,
    ),
  );

  Future<String> _resolveHabitTimezone() async {
    final timezone = await _deviceTimezone();
    if (timezone.isEmpty) {
      throw StateError('Device IANA timezone is unavailable.');
    }
    return timezone;
  }

  Widget _withHabitTimezone(Widget Function(String timezone) builder) {
    return FutureBuilder<String>(
      future: _habitTimezoneFuture,
      builder: (context, snapshot) {
        final timezone = snapshot.data;
        if (timezone != null) return builder(timezone);
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('无法读取设备时区，习惯功能暂不可用'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _habitTimezoneFuture = _resolveHabitTimezone();
                        });
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }

  CurrentUserResponseDto? get _currentUserOrNull =>
      _authDeps.session.currentUser;

  Widget _requireUser(Widget Function(CurrentUserResponseDto user) builder) {
    final user = _currentUserOrNull;
    if (user == null) {
      return const _MissingUserPage();
    }
    return builder(user);
  }

  @override
  Widget build(BuildContext context) {
    return RingSessionHost(
      controller: _activeRingController,
      navigatorKey: _navigatorKey,
      child: ListenableBuilder(
        listenable: _appearanceController,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          restorationScopeId: 'excellent-calendar-app',
          title: 'Excellent Calendar',
          debugShowCheckedModeBanner: false,
          locale: excellentCalendarLocale,
          localizationsDelegates: excellentCalendarLocalizationsDelegates,
          supportedLocales: excellentCalendarSupportedLocales,
          theme: buildHabitAppTheme(
            seedColor: colorForHabitToken(_appearanceController.token),
            brightness: Brightness.light,
          ),
          darkTheme: buildHabitAppTheme(
            seedColor: colorForHabitToken(_appearanceController.token),
            brightness: Brightness.dark,
          ),
          themeMode: ThemeMode.system,
          initialRoute: widget.initialRoute,
          onGenerateInitialRoutes: widget.initialRoute == '/auth-check'
              ? (_) => AppRouter.initialAuthCheckRoutes(
                  authCheckBuilder: (_) => AuthCheckPage(
                    startupCheck: _authDeps.startupCheck,
                    navigator: _authDeps.navigator,
                  ),
                )
              : null,
          onGenerateRoute: (settings) => AppRouter.onGenerateRoute(
            settings,
            todayBuilder: _buildToday,
            anniversaryListBuilder: _buildAnniversaryList,
            anniversaryDetailBuilder: _buildAnniversaryDetail,
            habitListBuilder: _buildHabitList,
            habitCreateBuilder: _buildHabitCreate,
            habitDetailBuilder: _buildHabitDetail,
            appearanceBuilder: (_) =>
                AppearancePage(controller: _appearanceController),
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
            authCheckBuilder: (_) => AuthCheckPage(
              startupCheck: _authDeps.startupCheck,
              navigator: _authDeps.navigator,
            ),
            loginBuilder: (_) => LoginPage(
              authService: _authDeps.authService,
              navigator: _authDeps.navigator,
            ),
            registerBuilder: (_) => RegisterPage(
              authService: _authDeps.authService,
              localeProvider: _localeTag,
              timezoneProvider: _deviceTimezone,
              navigator: _authDeps.navigator,
            ),
            verificationBuilder: (_) => EmailVerificationPage(
              authService: _authDeps.authService,
              navigator: _authDeps.navigator,
            ),
            forgotPasswordBuilder: (_) => ForgotPasswordPage(
              authService: _authDeps.authService,
              navigator: _authDeps.navigator,
            ),
            resetPasswordBuilder: (_) => ResetPasswordPage(
              authService: _authDeps.authService,
              navigator: _authDeps.navigator,
              onResetSucceeded: _authDeps.logoutService.clearLocalSession,
            ),
            profileBuilder: (_) => ProfilePage(
              authService: _authDeps.authService,
              session: _authDeps.session,
              navigator: _authDeps.navigator,
              onOpenAppearance: () =>
                  _authDeps.navigator.push('/settings/appearance'),
            ),
            editProfileBuilder: (_) => _requireUser(
              (user) => EditProfilePage(
                authService: _authDeps.authService,
                initialUser: user,
              ),
            ),
            changeEmailBuilder: (_) => _requireUser(
              (user) => ChangeEmailPage(
                authService: _authDeps.authService,
                initialUser: user,
                navigator: _authDeps.navigator,
              ),
            ),
            changePasswordBuilder: (_) => ChangePasswordPage(
              authService: _authDeps.authService,
              navigator: _authDeps.navigator,
            ),
            accountSecurityBuilder: (_) => AccountSecurityPage(
              logoutService: _authDeps.logoutService,
              navigator: _authDeps.navigator,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _calendarController.dispose();
    _searchController.dispose();
    _activeRingController.dispose();
    _notificationBootstrap.dispose();
    _appearanceController.dispose();
    if (_ownsAuthDeps) {
      _authDeps.session.dispose();
    }
    super.dispose();
  }
}

/// Shown when an authenticated-only page is opened without a user loaded.
class _MissingUserPage extends StatelessWidget {
  const _MissingUserPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('用户信息尚未加载'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

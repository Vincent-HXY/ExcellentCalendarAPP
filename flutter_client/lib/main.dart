import 'package:flutter/material.dart';

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/bootstrap/category_repository_composition.dart';
import 'app/bootstrap/notification_permission_controller.dart';
import 'app/routing/app_route_navigator.dart';
import 'app/routing/app_router.dart';
import 'app/routing/auth_navigator.dart';
import 'app/routing/notification_tap_router.dart';
import 'application/anniversary/app_clock.dart';
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
import 'application/timezone/timezone_application_service.dart';
import 'boundary_adapters/backend_api/backend_api_config.dart';
import 'boundary_adapters/backend_api/dio_backend_api_client.dart';
import 'boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_ring_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'data/anniversary/fake_anniversary_share_gateway.dart';
import 'data/anniversary/native_anniversary_gateway.dart';
import 'data/auth/dio_auth_gateway.dart';
import 'boundary_adapters/dart_method_channel/method_channel_refresh_token_secure_store.dart';
import 'data/user/dio_user_gateway.dart';
import 'data/user/user_profile_file_cache.dart';
import 'gateway_interfaces/anniversary_gateway.dart';
import 'gateway_interfaces/category_repository.dart';
import 'gateway_interfaces/ring_native_gateway.dart';
import 'application/ring/active_ring_session_controller.dart';
import 'gateway_interfaces/refresh_token_secure_store_gateway.dart';
import 'native_contract/user/current_user_response_dto.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/anniversary/pages/anniversary_detail_page.dart';
import 'presentation/anniversary/pages/anniversary_list_page.dart';
import 'presentation/auth/pages/auth_check_page.dart';
import 'presentation/auth/pages/email_verification_page.dart';
import 'presentation/auth/pages/forgot_password_page.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/auth/pages/register_page.dart';
import 'presentation/auth/pages/reset_password_page.dart';
import 'presentation/event_detail/pages/event_detail_flow_page.dart';
import 'presentation/inbox/inbox_page.dart';
import 'presentation/ring/active_ring_session_page.dart';
import 'presentation/ring/ring_session_host.dart';
import 'presentation/ring/ring_settings_page.dart';
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
    this.authDependencies,
    super.key,
  });

  final AppClock anniversaryClock;
  final CategoryRepository categoryRepository;
  final RingNativeGateway ringGateway;
  final AuthDependencies? authDependencies;

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
  late final ActiveRingSessionController _activeRingController;
  late final MethodChannelTimezoneAdapter _timezoneGateway;
  late final AuthDependencies _authDeps;
  bool _ownsAuthDeps = false;

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
    _timezoneGateway = MethodChannelTimezoneAdapter();
    final timezoneGateway = _timezoneGateway;
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
      permissionController: _notificationPermissionController,
    );
  }

  Widget _buildAnniversaryDetail(BuildContext context, String anniversaryId) {
    return AnniversaryDetailPage(
      anniversaryId: anniversaryId,
      gateway: _anniversaryGateway,
      shareGateway: _anniversaryShareGateway,
      clock: _anniversaryClock,
      permissionController: _notificationPermissionController,
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
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Excellent Calendar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38B9C5)),
          fontFamily: 'Roboto',
          useMaterial3: true,
        ),
        initialRoute: '/auth-check',
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
    );
  }

  @override
  void dispose() {
    _activeRingController.dispose();
    _notificationBootstrap.dispose();
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

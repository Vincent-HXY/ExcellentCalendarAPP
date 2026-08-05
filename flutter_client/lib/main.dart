import 'package:flutter/material.dart';

import 'app/bootstrap/app_notification_bootstrap.dart';
import 'app/routing/app_route_navigator.dart';
import 'app/routing/app_router.dart';
import 'app/routing/notification_tap_router.dart';
import 'application/event/create_event_use_case.dart';
import 'application/event/complete_event_use_case.dart';
import 'application/event/read_events_use_case.dart';
import 'application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'auth/auth_api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/auth_http_client.dart';
import 'auth/auth_refresh_token_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'presentation/app_notification_host.dart';
import 'presentation/inbox/inbox_page.dart';
import 'presentation/splash/splash_page.dart';

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

  // Auth infrastructure
  late final AuthConfig _authConfig;
  late final AuthRefreshTokenAdapter _refreshTokenAdapter;
  late final AuthHttpClient _authHttpClient;
  late final AuthApiClient _authApiClient;
  late final AuthController _authController;

  // Existing infrastructure
  late final MethodChannelEventAdapter _eventGateway;
  late final ReconcileReminderScheduleUseCase _reconcileReminderScheduleUseCase;
  late final CreateEventUseCase _createEventUseCase;
  late final AppNotificationBootstrap _notificationBootstrap;

  @override
  void initState() {
    super.initState();

    // Initialize auth infrastructure
    _authConfig = AuthConfig();
    _refreshTokenAdapter = AuthRefreshTokenAdapter();
    _authHttpClient = AuthHttpClient(
      config: _authConfig,
      refreshTokenAdapter: _refreshTokenAdapter,
    );
    _authApiClient = AuthApiClient(_authHttpClient);
    _authController = AuthController(
      httpClient: _authHttpClient,
      apiClient: _authApiClient,
      refreshTokenAdapter: _refreshTokenAdapter,
    );

    // Set up refresh failure callback
    _authHttpClient.onRefreshFailed = () {
      _authController.logout();
    };

    // Initialize existing infrastructure
    _eventGateway = MethodChannelEventAdapter();
    final reminderGateway = MethodChannelReminderAdapter();
    _reconcileReminderScheduleUseCase = ReconcileReminderScheduleUseCase(
      reminderGateway,
    );
    _createEventUseCase = CreateEventUseCase(
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

  @override
  void dispose() {
    _notificationBootstrap.dispose();
    _authController.dispose();
    super.dispose();
  }

  Widget _buildToday(BuildContext context) {
    return AppNotificationHost(
      bootstrap: _notificationBootstrap,
      child: InboxPage(
        readEventsUseCase: ReadEventsUseCase(_eventGateway),
        createEventUseCase: _createEventUseCase,
        completeEventUseCase: CompleteEventUseCase(
          _eventGateway,
          reconcileReminderScheduleUseCase: _reconcileReminderScheduleUseCase,
        ),
      ),
    );
  }

  void _onAuthenticated() {
    _navigatorKey.currentState?.pushReplacementNamed('/today');
  }

  void _onUnauthenticated() {
    _navigatorKey.currentState?.pushReplacementNamed('/login');
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
      initialRoute: '/splash',
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/splash';

        if (name == '/splash') {
          return MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/splash'),
            builder: (_) => SplashPage(
              authController: _authController,
              onAuthenticated: _onAuthenticated,
              onUnauthenticated: _onUnauthenticated,
            ),
          );
        }

        if (name == '/login') {
          // Placeholder: will be replaced with the actual login page
          return MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/login'),
            builder: (_) => Scaffold(
              backgroundColor: const Color(0xFFE6F8FA),
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Login Page',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Login page will be implemented in the next phase.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              // Demo: simulate login
                              _authController.login(
                                email: 'user@example.com',
                                password: 'password',
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF38B9C5),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Demo Login',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Fall through to the existing router for other routes
        if (name == '/today' || name == '/') {
          return MaterialPageRoute<void>(
            settings: const RouteSettings(name: '/today'),
            builder: (_) => _buildToday(context),
          );
        }

        return AppRouter.onGenerateRoute(settings, todayBuilder: (_) => _buildToday(context));
      },
    );
  }
}
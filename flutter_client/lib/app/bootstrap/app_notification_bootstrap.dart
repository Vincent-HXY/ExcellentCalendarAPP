import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/reminder/schedule_pending_reminders_use_case.dart';
import '../../gateway_interfaces/notification_native_gateway.dart';
import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import '../../native_contract/notification/open_notification_settings_request_dto.dart';
import '../../native_contract/notification/request_notification_permission_dto.dart';
import '../../native_contract/reminder/schedule_pending_reminders_dto.dart';
import '../routing/notification_tap_router.dart';

enum NotificationBootstrapPhase { idle, starting, ready, degraded }

class AppNotificationBootstrapState {
  const AppNotificationBootstrapState({
    this.phase = NotificationBootstrapPhase.idle,
    this.permissionStatus,
    this.needsPermissionExplanation = false,
    this.permissionRequestHandled = false,
    this.shouldOfferSettings = false,
    this.lastScheduleResponse,
    this.errorMessage,
  });

  final NotificationBootstrapPhase phase;
  final NotificationPermissionStatusDto? permissionStatus;
  final bool needsPermissionExplanation;
  final bool permissionRequestHandled;
  final bool shouldOfferSettings;
  final SchedulePendingRemindersResponseDto? lastScheduleResponse;
  final String? errorMessage;

  AppNotificationBootstrapState copyWith({
    NotificationBootstrapPhase? phase,
    NotificationPermissionStatusDto? permissionStatus,
    bool? needsPermissionExplanation,
    bool? permissionRequestHandled,
    bool? shouldOfferSettings,
    SchedulePendingRemindersResponseDto? lastScheduleResponse,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AppNotificationBootstrapState(
      phase: phase ?? this.phase,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      needsPermissionExplanation:
          needsPermissionExplanation ?? this.needsPermissionExplanation,
      permissionRequestHandled:
          permissionRequestHandled ?? this.permissionRequestHandled,
      shouldOfferSettings: shouldOfferSettings ?? this.shouldOfferSettings,
      lastScheduleResponse: lastScheduleResponse ?? this.lastScheduleResponse,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class AppNotificationBootstrap extends ChangeNotifier {
  AppNotificationBootstrap({
    required NotificationNativeGateway notificationGateway,
    required SchedulePendingRemindersUseCase schedulePendingRemindersUseCase,
    required NotificationTapRouter notificationTapRouter,
  }) : _notificationGateway = notificationGateway,
       _schedulePendingRemindersUseCase = schedulePendingRemindersUseCase,
       _notificationTapRouter = notificationTapRouter;

  final NotificationNativeGateway _notificationGateway;
  final SchedulePendingRemindersUseCase _schedulePendingRemindersUseCase;
  final NotificationTapRouter _notificationTapRouter;
  StreamSubscription<NotificationOpenedEvent>? _openedSubscription;
  AppNotificationBootstrapState _state = const AppNotificationBootstrapState();
  bool _started = false;
  bool _disposed = false;

  AppNotificationBootstrapState get state => _state;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _setState(_state.copyWith(phase: NotificationBootstrapPhase.starting));

    // Attach first so warm-start taps cannot race notification.initialize.
    _openedSubscription = _notificationGateway.openedEvents().listen(
      _handleOpenedEvent,
    );

    final initialization = await _notificationGateway.initialize();
    if (!initialization.result.ok) {
      _setDegraded(_nativeError(initialization.result.error?.message));
    }

    await _refreshPermissionStatus(showExplanation: true);
    await _scheduleIfAllowed();

    final initialPayload = await _notificationGateway.getInitialTapPayload();
    if (initialPayload.result.ok) {
      final payload = initialPayload.result.data!.payload;
      if (payload != null) _notificationTapRouter.open(payload);
    } else {
      _notificationTapRouter.fallback(
        _nativeError(initialPayload.result.error?.message),
      );
    }

    if (_state.phase != NotificationBootstrapPhase.degraded) {
      _setState(_state.copyWith(phase: NotificationBootstrapPhase.ready));
    }
  }

  Future<void> requestPermissions() async {
    final status = _state.permissionStatus;
    if (status == null || _state.permissionRequestHandled) return;
    final requestNotification = !status.canPostNotifications;
    final requestExactAlarm = !status.canScheduleExactAlarms;
    if (!requestNotification && !requestExactAlarm) return;

    _setState(
      _state.copyWith(
        permissionRequestHandled: true,
        needsPermissionExplanation: false,
      ),
    );
    final invocation = await _notificationGateway.requestPermission(
      RequestNotificationPermissionRequestDto(
        requestNotificationPermission: requestNotification,
        requestExactAlarmPermission: requestExactAlarm,
        source: NotificationPermissionRequestSource.appStartup,
      ),
    );
    if (!invocation.result.ok) {
      _setDegraded(_nativeError(invocation.result.error?.message));
      return;
    }
    final response = invocation.result.data!;
    _setState(
      _state.copyWith(
        shouldOfferSettings: response.shouldOpenSettings,
        errorMessage: response.message,
      ),
    );
    await _refreshPermissionStatus(showExplanation: false);
    await _scheduleIfAllowed();
  }

  void dismissPermissionExplanation() {
    _setState(
      _state.copyWith(
        permissionRequestHandled: true,
        needsPermissionExplanation: false,
        shouldOfferSettings: true,
      ),
    );
  }

  Future<void> openNotificationSettings() async {
    final status = _state.permissionStatus;
    final target =
        status != null &&
            status.canPostNotifications &&
            !status.canScheduleExactAlarms
        ? NotificationSettingsTarget.exactAlarm
        : NotificationSettingsTarget.notification;
    await _notificationGateway.openSettings(
      OpenNotificationSettingsRequestDto(settingsTarget: target),
    );
  }

  Future<void> onAppResumed() async {
    if (!_started) return;
    await _refreshPermissionStatus(showExplanation: false);
    await _scheduleIfAllowed();
  }

  Future<void> schedulePendingAfterMutation() => _scheduleIfAllowed();

  Future<void> _refreshPermissionStatus({required bool showExplanation}) async {
    final invocation = await _notificationGateway.permissionStatus();
    if (!invocation.result.ok) {
      _setDegraded(_nativeError(invocation.result.error?.message));
      return;
    }
    final status = invocation.result.data!;
    final permissionMissing =
        !status.canPostNotifications || !status.canScheduleExactAlarms;
    _setState(
      _state.copyWith(
        permissionStatus: status,
        needsPermissionExplanation:
            showExplanation &&
            permissionMissing &&
            !_state.permissionRequestHandled,
        shouldOfferSettings:
            _state.permissionRequestHandled && permissionMissing,
        clearError: true,
      ),
    );
  }

  Future<void> _scheduleIfAllowed() async {
    final status = _state.permissionStatus;
    if (status == null ||
        !status.canPostNotifications ||
        !status.canScheduleExactAlarms) {
      return;
    }
    final invocation = await _schedulePendingRemindersUseCase.execute();
    if (invocation.result.ok) {
      _setState(
        _state.copyWith(
          lastScheduleResponse: invocation.result.data,
          clearError: true,
        ),
      );
    } else {
      _setDegraded(_nativeError(invocation.result.error?.message));
    }
  }

  void _handleOpenedEvent(NotificationOpenedEvent event) {
    switch (event) {
      case NotificationOpenedPayload(:final payload):
        _notificationTapRouter.open(payload);
      case NotificationOpenedFailure(:final message):
        _notificationTapRouter.fallback(message);
    }
  }

  String _nativeError(String? message) =>
      message ?? 'Native notification operation failed.';

  void _setDegraded(String message) {
    _setState(
      _state.copyWith(
        phase: NotificationBootstrapPhase.degraded,
        errorMessage: message,
      ),
    );
  }

  void _setState(AppNotificationBootstrapState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_openedSubscription?.cancel());
    super.dispose();
  }
}

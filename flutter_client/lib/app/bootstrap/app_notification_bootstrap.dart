import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/reminder/reconcile_reminder_schedule_use_case.dart';
import '../../gateway_interfaces/notification_native_gateway.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../routing/notification_tap_router.dart';
import 'notification_permission_controller.dart';
import 'reminder_schedule_lifecycle_coordinator.dart';

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
  final ReconcileReminderScheduleResponseDto? lastScheduleResponse;
  final String? errorMessage;

  AppNotificationBootstrapState copyWith({
    NotificationBootstrapPhase? phase,
    NotificationPermissionStatusDto? permissionStatus,
    bool? needsPermissionExplanation,
    bool? permissionRequestHandled,
    bool? shouldOfferSettings,
    ReconcileReminderScheduleResponseDto? lastScheduleResponse,
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
    required ReconcileReminderScheduleUseCase reconcileReminderScheduleUseCase,
    required NotificationTapRouter notificationTapRouter,
  }) : _notificationGateway = notificationGateway,
       _permissionController = NotificationPermissionController(
         notificationGateway,
       ),
       _scheduleCoordinator = ReminderScheduleLifecycleCoordinator(
         reconcileReminderScheduleUseCase,
       ),
       _notificationTapRouter = notificationTapRouter;

  final NotificationNativeGateway _notificationGateway;
  final NotificationPermissionController _permissionController;
  final ReminderScheduleLifecycleCoordinator _scheduleCoordinator;
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
      return;
    }

    await _refreshPermissionStatus(showExplanation: true);
    await _reconcileIfAllowed(ReminderScheduleTrigger.appStart);

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
    if (status.canPostNotifications && status.canScheduleExactAlarms) return;

    _setState(
      _state.copyWith(
        permissionRequestHandled: true,
        needsPermissionExplanation: false,
      ),
    );
    final result = await _permissionController.request(status);
    if (!result.succeeded) {
      _setDegraded(
        result.errorMessage ?? 'Native notification operation failed.',
      );
      return;
    }
    _setState(
      _state.copyWith(
        shouldOfferSettings: result.shouldOpenSettings,
        errorMessage: result.message,
      ),
    );
    final refreshed = await _refreshPermissionStatus(showExplanation: false);
    if (!refreshed) return;
    await _reconcileIfAllowed(ReminderScheduleTrigger.manualRetry, force: true);
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
    await _permissionController.openSettings(_state.permissionStatus);
  }

  Future<void> onAppResumed() async {
    if (!_started) return;
    final refreshed = await _refreshPermissionStatus(showExplanation: false);
    if (!refreshed) return;
    await _reconcileIfAllowed(ReminderScheduleTrigger.appResume);
  }

  Future<void> schedulePendingAfterMutation() =>
      _reconcileIfAllowed(ReminderScheduleTrigger.mutation, force: true);

  Future<bool> _refreshPermissionStatus({required bool showExplanation}) async {
    final result = await _permissionController.refresh();
    if (!result.succeeded) {
      _setDegraded(
        result.errorMessage ?? 'Native notification operation failed.',
      );
      return false;
    }
    final status = result.status!;
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
    return true;
  }

  Future<void> _reconcileIfAllowed(
    ReminderScheduleTrigger triggerSource, {
    bool force = false,
  }) async {
    final result = await _scheduleCoordinator.reconcileIfAllowed(
      permissionStatus: _state.permissionStatus,
      triggerSource: triggerSource,
      force: force,
    );
    if (result.failed) {
      _setDegraded(result.errorMessage!);
    } else if (result.response != null) {
      _setState(
        _state.copyWith(
          lastScheduleResponse: result.response,
          clearError: true,
        ),
      );
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

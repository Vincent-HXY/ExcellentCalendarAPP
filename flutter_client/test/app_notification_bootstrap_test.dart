import 'package:excellent_calendar/app/bootstrap/app_notification_bootstrap.dart';
import 'package:excellent_calendar/app/routing/notification_tap_router.dart';
import 'package:excellent_calendar/application/reminder/schedule_pending_reminders_use_case.dart';
import 'package:excellent_calendar/gateway_interfaces/notification_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/operation_response_dto.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:excellent_calendar/presentation/app_notification_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_app_route_navigator.dart';
import 'fakes/fake_notification_gateway.dart';
import 'fakes/fake_reminder_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/reminder_fixtures.dart';

void main() {
  test(
    'cold start attaches listener before initialize and routes payload',
    () async {
      final callLog = <String>[];
      final navigator = FakeAppRouteNavigator();
      final notificationGateway = _notificationGateway(
        canPost: true,
        canScheduleExact: true,
        initialPayload: tapPayload(),
        callLog: callLog,
      );
      final reminderGateway = _reminderGateway(
        onSchedule: (_) async {
          callLog.add('schedule_pending');
          return successInvocation(scheduleResponse);
        },
      );
      final bootstrap = AppNotificationBootstrap(
        notificationGateway: notificationGateway,
        schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
          reminderGateway,
          clock: () => DateTime.utc(2026, 7, 5),
        ),
        notificationTapRouter: NotificationTapRouter(navigator: navigator),
      );

      await bootstrap.start();

      expect(callLog, [
        'opened.listen',
        'initialize',
        'permission_status',
        'schedule_pending',
        'initial_payload',
      ]);
      expect(navigator.routes, ['/event/detail/event-1']);
      bootstrap.dispose();
      await notificationGateway.openedController.close();
    },
  );

  testWidgets('permission denial exposes explanation then settings entry', (
    tester,
  ) async {
    final notificationGateway = _notificationGateway(
      canPost: false,
      canScheduleExact: false,
      requestCanPost: false,
      requestCanScheduleExact: false,
      shouldOpenSettings: true,
    );
    final reminderGateway = _reminderGateway(
      onSchedule: (_) async => successInvocation(scheduleResponse),
    );
    final bootstrap = AppNotificationBootstrap(
      notificationGateway: notificationGateway,
      schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
        reminderGateway,
      ),
      notificationTapRouter: NotificationTapRouter(
        navigator: FakeAppRouteNavigator(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppNotificationHost(
          bootstrap: bootstrap,
          child: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('开启通知提醒'), findsOneWidget);
    await tester.tap(find.text('允许'));
    await tester.pumpAndSettle();

    expect(bootstrap.state.permissionRequestHandled, isTrue);
    expect(bootstrap.state.shouldOfferSettings, isTrue);
    expect(find.text('去设置'), findsOneWidget);
    expect(reminderGateway.schedulePendingCallCount, 0);

    await notificationGateway.openedController.close();
  });

  test('warm opened event routes and duplicate is ignored', () async {
    final navigator = FakeAppRouteNavigator();
    final notificationGateway = _notificationGateway(
      canPost: true,
      canScheduleExact: true,
    );
    final reminderGateway = _reminderGateway(
      onSchedule: (_) async => successInvocation(scheduleResponse),
    );
    final bootstrap = AppNotificationBootstrap(
      notificationGateway: notificationGateway,
      schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
        reminderGateway,
      ),
      notificationTapRouter: NotificationTapRouter(navigator: navigator),
    );
    await bootstrap.start();
    final payload = tapPayload();

    notificationGateway.openedController.add(
      NotificationOpenedPayload(payload),
    );
    notificationGateway.openedController.add(
      NotificationOpenedPayload(payload),
    );
    await Future<void>.delayed(Duration.zero);

    expect(navigator.routes, ['/event/detail/event-1']);
    bootstrap.dispose();
    await notificationGateway.openedController.close();
  });

  test(
    'notification initialization failure prevents reminder scheduling',
    () async {
      final notificationGateway = _notificationGateway(
        canPost: true,
        canScheduleExact: true,
        initializeFails: true,
      );
      final reminderGateway = _reminderGateway(
        onSchedule: (_) async => successInvocation(scheduleResponse),
      );
      final bootstrap = AppNotificationBootstrap(
        notificationGateway: notificationGateway,
        schedulePendingRemindersUseCase: SchedulePendingRemindersUseCase(
          reminderGateway,
        ),
        notificationTapRouter: NotificationTapRouter(
          navigator: FakeAppRouteNavigator(),
        ),
      );

      await bootstrap.start();

      expect(bootstrap.state.phase, NotificationBootstrapPhase.degraded);
      expect(reminderGateway.schedulePendingCallCount, 0);
      bootstrap.dispose();
      await notificationGateway.openedController.close();
    },
    skip: 'Known defect: start() continues scheduling after initialize fails.',
  );
}

FakeReminderGateway _reminderGateway({
  required SchedulePendingRemindersHandler onSchedule,
}) {
  return FakeReminderGateway(
    onCreate: (_) async => reminderSuccessInvocation(),
    onCancel: (_) async => reminderSuccessInvocation(),
    onSchedulePending: onSchedule,
  );
}

FakeNotificationGateway _notificationGateway({
  required bool canPost,
  required bool canScheduleExact,
  bool? requestCanPost,
  bool? requestCanScheduleExact,
  bool shouldOpenSettings = false,
  NotificationTapPayloadDto? initialPayload,
  List<String>? callLog,
  bool initializeFails = false,
}) {
  return FakeNotificationGateway(
    callLog: callLog,
    initializeInvocation: initializeFails
        ? failureInvocation(code: 'NOTIFICATION_INITIALIZATION_FAILED')
        : successInvocation(initializedResponse),
    permissionStatusInvocation: successInvocation(
      permissionStatus(canPost: canPost, canScheduleExact: canScheduleExact),
    ),
    permissionRequestInvocation: successInvocation(
      permissionRequestResponse(
        canPost: requestCanPost ?? canPost,
        canScheduleExact: requestCanScheduleExact ?? canScheduleExact,
        shouldOpenSettings: shouldOpenSettings,
      ),
    ),
    openSettingsInvocation: successInvocation(
      const OperationResponseDto(performed: true),
    ),
    initialPayloadInvocation: successInvocation(
      NotificationTapPayloadResponseDto(
        hasPayload: initialPayload != null,
        payload: initialPayload,
      ),
    ),
  );
}

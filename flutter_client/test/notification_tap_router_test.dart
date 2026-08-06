import 'package:excellent_calendar/app/routing/notification_tap_router.dart';
import 'package:excellent_calendar/native_contract/notification/notification_contract_enums.dart';
import 'package:excellent_calendar/native_contract/notification/notification_tap_payload_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_app_route_navigator.dart';
import 'fixtures/notification_fixtures.dart';

void main() {
  test('event occurrence route is encoded and deduplicated by delivery id', () {
    final navigator = FakeAppRouteNavigator();
    final router = NotificationTapRouter(navigator: navigator);
    final first = _tapPayload(
      targetId: 'event/../../today?source=notification#fragment',
      occurrenceKey: 'occurrence/?value=1&next=/today#fragment',
    );

    expect(router.open(first), isTrue);
    expect(
      router.open(
        _tapPayload(
          notificationId: 'notification-2',
          deliveryId: first.deliveryId,
          deliveryAttemptId: 'delivery-attempt-2',
          reminderId: 'reminder-2',
        ),
      ),
      isFalse,
    );

    final route = Uri.parse(navigator.routes.single);
    expect(route.pathSegments, [
      'event',
      'detail',
      'event/../../today?source=notification#fragment',
    ]);
    expect(
      route.queryParameters['occurrence_key'],
      'occurrence/?value=1&next=/today#fragment',
    );
    expect(navigator.routes.single, startsWith('/event/detail/'));
  });

  test(
    'separate deliveries are not collapsed by reminder or notification id',
    () {
      final navigator = FakeAppRouteNavigator();
      final router = NotificationTapRouter(navigator: navigator);

      expect(router.open(_tapPayload()), isTrue);
      expect(
        router.open(
          _tapPayload(
            deliveryId: 'delivery-2',
            deliveryAttemptId: 'delivery-attempt-2',
          ),
        ),
        isTrue,
      );

      expect(navigator.routes, [
        '/event/detail/event-1',
        '/event/detail/event-1',
      ]);
    },
  );

  test('cold and warm routers produce the same occurrence destination', () {
    final coldNavigator = FakeAppRouteNavigator();
    final warmNavigator = FakeAppRouteNavigator();
    final payload = _tapPayload(occurrenceKey: 'occurrence-1');

    NotificationTapRouter(navigator: coldNavigator).open(payload);
    NotificationTapRouter(navigator: warmNavigator).open(payload);

    expect(coldNavigator.routes, [
      '/event/detail/event-1?occurrence_key=occurrence-1',
    ]);
    expect(warmNavigator.routes, coldNavigator.routes);
  });

  test('recovery summary always routes to today', () {
    final navigator = FakeAppRouteNavigator();
    final router = NotificationTapRouter(navigator: navigator);
    router.open(
      tapPayload(targetType: NotificationTargetType.reminderRecoveryBatch),
    );
    expect(navigator.routes, ['/today']);
  });
}

NotificationTapPayloadDto _tapPayload({
  String notificationId = 'notification-1',
  String deliveryId = 'delivery-1',
  String deliveryAttemptId = 'delivery-attempt-1',
  String? reminderId = 'reminder-1',
  String targetId = 'event-1',
  String? occurrenceKey,
}) {
  return NotificationTapPayloadDto(
    notificationId: notificationId,
    deliveryId: deliveryId,
    deliveryAttemptId: deliveryAttemptId,
    kind: NotificationKind.reminder,
    reminderId: reminderId,
    recoveryBatchId: null,
    targetType: NotificationTargetType.event,
    targetId: targetId,
    occurrenceKey: occurrenceKey,
    route: null,
    openedAt: DateTime.utc(2026, 8, 5, 10),
  );
}

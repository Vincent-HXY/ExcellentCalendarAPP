import 'package:excellent_calendar/app/routing/notification_tap_router.dart';
import 'package:excellent_calendar/native_contract/notification/notification_contract_enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_app_route_navigator.dart';
import 'fixtures/notification_fixtures.dart';

void main() {
  test(
    'routes supported targets and deduplicates notification/reminder ids',
    () {
      final navigator = FakeAppRouteNavigator();
      final router = NotificationTapRouter(navigator: navigator);
      final first = tapPayload();

      expect(router.open(first), isTrue);
      expect(router.open(first), isFalse);
      expect(
        router.open(
          tapPayload(
            notificationId: 'notification-2',
            reminderId: first.reminderId,
          ),
        ),
        isFalse,
      );
      expect(navigator.routes, ['/event/detail/event-1']);
    },
  );

  test('unsupported dated_message target falls back to today', () {
    final navigator = FakeAppRouteNavigator();
    final router = NotificationTapRouter(navigator: navigator);
    router.open(
      tapPayload(targetType: NotificationTargetType.reminderRecoveryBatch),
    );
    expect(navigator.routes, ['/today']);
  });
}

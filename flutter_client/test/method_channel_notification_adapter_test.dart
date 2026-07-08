import 'dart:async';

import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_notification_adapter.dart';
import 'package:excellent_calendar/gateway_interfaces/notification_native_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses notification.initialize with explicit empty request', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return {
            'ok': true,
            'data': {
              'initialized': true,
              'notification_channel_ready': true,
              'default_channel_id': 'calendar-reminders',
              'sdk_int': 35,
              'message': null,
            },
            'error': null,
            'contract_version': 1,
            'request_id': 'initialize-1',
          };
        });

    final result = await MethodChannelNotificationAdapter(
      channel: channel,
      openedEventStream: const Stream.empty(),
    ).initialize();

    expect(captured!.method, 'notification.initialize');
    expect(captured!.arguments, <String, dynamic>{});
    expect(result.result.data!.initialized, isTrue);
  });

  test(
    'normalizes EventChannel payload and reports malformed payload',
    () async {
      final controller = StreamController<Object?>();
      final adapter = MethodChannelNotificationAdapter(
        channel: channel,
        openedEventStream: controller.stream,
      );
      final events = <NotificationOpenedEvent>[];
      final subscription = adapter.openedEvents().listen(events.add);
      final streamDone = subscription.asFuture<void>();

      controller.add({
        'notification_id': 'notification-1',
        'reminder_id': 'reminder-1',
        'target_type': 'event',
        'target_id': 'event-1',
        'route': null,
        'opened_at': '2026-07-05T10:00:00.000Z',
      });
      controller.add({'target_type': 'unsupported'});
      await controller.close();
      await streamDone;

      expect(events.first, isA<NotificationOpenedPayload>());
      expect(events.last, isA<NotificationOpenedFailure>());
    },
  );
}

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
            'contract_version': 2,
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
        'notification_id': '11111111-1111-4111-8111-111111111111',
        'delivery_id': '22222222-2222-4222-8222-222222222222',
        'delivery_attempt_id': '33333333-3333-4333-8333-333333333333',
        'kind': 'reminder',
        'reminder_id': '44444444-4444-4444-8444-444444444444',
        'recovery_batch_id': null,
        'target_type': 'event',
        'target_id': '55555555-5555-4555-8555-555555555555',
        'occurrence_key': null,
        'route': null,
        'opened_at': '2026-07-05T10:00:00Z',
      });
      controller.add({'target_type': 'unsupported'});
      await controller.close();
      await streamDone;

      expect(events.first, isA<NotificationOpenedPayload>());
      expect(events.last, isA<NotificationOpenedFailure>());
    },
  );
}

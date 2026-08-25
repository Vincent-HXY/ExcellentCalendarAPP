import 'dart:async';

import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_ring_adapter.dart';
import 'package:excellent_calendar/gateway_interfaces/ring_native_gateway.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_request_dtos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/ring_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses every frozen ring method with typed snake_case payloads',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'ring.pick_ringtone') {
              return nativeSuccess({
                'selection_status': 'cancelled',
                'state': ringStateJson(),
              });
            }
            if (call.method == 'ring.snooze_active') {
              return nativeSuccess({
                'results': [
                  {
                    'delivery_id': deliveryId,
                    'status': 'succeeded',
                    'snoozed_reminder_id': snoozedReminderId,
                    'error': null,
                  },
                ],
                'succeeded_count': 1,
                'failed_count': 0,
                'state': ringStateJson(sequence: 2, sessionRevision: 2),
              });
            }
            return nativeSuccess(
              ringStateJson(sequence: 2, sessionRevision: 2),
            );
          });
      final adapter = MethodChannelRingAdapter(
        channel: channel,
        stateEventStream: const Stream.empty(),
      );
      final activeRequest = ActiveRingItemsRequestDto(
        runtimeInstanceId: runtimeId,
        sessionId: sessionId,
        expectedSessionRevision: 1,
        deliveryIds: [deliveryId],
      );

      await adapter.getState();
      await adapter.pickRingtone(
        const PickRingtoneRequestDto(expectedSettingsRevision: 1),
      );
      await adapter.updateSettings(
        const UpdateRingSettingsRequestDto(
          expectedSettingsRevision: 1,
          strongReminderEnabled: true,
        ),
      );
      await adapter.testRing(
        const RingTestRequestDto(
          action: RingTestAction.start,
          expectedSettingsRevision: 1,
        ),
      );
      await adapter.stopActive(activeRequest);
      await adapter.snoozeActive(activeRequest);
      await adapter.completeItem(
        const CompleteRingItemRequestDto(
          runtimeInstanceId: runtimeId,
          sessionId: sessionId,
          expectedSessionRevision: 1,
          deliveryId: deliveryId,
        ),
      );

      expect(calls.map((call) => call.method), [
        'ring.get_state',
        'ring.pick_ringtone',
        'ring.update_settings',
        'ring.test',
        'ring.stop_active',
        'ring.snooze_active',
        'ring.complete_item',
      ]);
      expect(calls[2].arguments, {
        'expected_settings_revision': 1,
        'strong_reminder_enabled': true,
      });
      expect(calls[4].arguments, {
        'runtime_instance_id': runtimeId,
        'session_id': sessionId,
        'expected_session_revision': 1,
        'delivery_ids': [deliveryId],
      });
    },
  );

  test('normalizes ring events and surfaces malformed event data', () async {
    final stream = StreamController<Object?>();
    final adapter = MethodChannelRingAdapter(
      channel: channel,
      stateEventStream: stream.stream,
    );
    final events = <RingStateEvent>[];
    final subscription = adapter.stateEvents().listen(events.add);
    final done = subscription.asFuture<void>();

    stream.add({'reason': 'session_changed', 'state': ringStateJson()});
    stream.add({'reason': 'future_reason', 'state': ringStateJson()});
    await stream.close();
    await done;

    expect(events.first, isA<RingStateChanged>());
    expect(events.last, isA<RingStateEventFailure>());
  });
}

import 'dart:async';

import 'package:excellent_calendar/application/ring/active_ring_session_controller.dart';
import 'package:excellent_calendar/application/ring/ring_settings_controller.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/gateway_interfaces/ring_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/event_detail_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_request_dtos.dart';
import 'package:excellent_calendar/native_contract/ring/ring_state_dtos.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_ring_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/ring_fixtures.dart';

void main() {
  test(
    'settings subscribes before get_state and ignores stale snapshots',
    () async {
      final calls = <String>[];
      final gateway = FakeRingGateway(
        callLog: calls,
        onGetState: () async =>
            successInvocation(ringSnapshot(sequence: 5, settingsRevision: 5)),
      );
      final controller = RingSettingsController(gateway: gateway);

      await controller.initialize();
      gateway.eventController.add(
        RingStateChanged(
          RingStateChangedEventDto(
            reason: RingStateChangeReason.settingsChanged,
            state: ringSnapshot(sequence: 5, settingsRevision: 99),
          ),
        ),
      );
      gateway.eventController.add(
        RingStateChanged(
          RingStateChangedEventDto(
            reason: RingStateChangeReason.settingsChanged,
            state: ringSnapshot(sequence: 6, settingsRevision: 6),
          ),
        ),
      );

      expect(calls.take(2), ['state_events', 'get_state']);
      expect(controller.settings!.revision, 6);
      controller.dispose();
      await gateway.eventController.close();
    },
  );

  test('active controller rejects events from a retired runtime', () async {
    final gateway = FakeRingGateway(
      onGetState: () async => successInvocation(
        ringSnapshot(
          sequence: 5,
          sessionRevision: 1,
          activeItems: [ringItem()],
        ),
      ),
    );
    final controller = ActiveRingSessionController(
      ringGateway: gateway,
      eventGateway: _EventDetailGateway(),
    );
    await controller.initialize();

    gateway.eventController.add(
      RingStateChanged(
        RingStateChangedEventDto(
          reason: RingStateChangeReason.sessionChanged,
          state: ringSnapshot(sequence: 99),
        ),
      ),
    );
    expect(controller.hasActiveSession, isTrue);

    gateway.eventController.add(
      RingStateChanged(
        RingStateChangedEventDto(
          reason: RingStateChangeReason.sessionRecovered,
          state: ringSnapshot(
            runtimeInstanceId: secondRuntimeId,
            sequence: 0,
            sessionRevision: 1,
          ),
        ),
      ),
    );
    gateway.eventController.add(
      RingStateChanged(
        RingStateChangedEventDto(
          reason: RingStateChangeReason.sessionChanged,
          state: ringSnapshot(
            sequence: 99,
            sessionRevision: 2,
            activeItems: [ringItem()],
          ),
        ),
      ),
    );

    expect(controller.snapshot!.runtimeInstanceId, secondRuntimeId);
    expect(controller.hasActiveSession, isFalse);
    controller.dispose();
    await gateway.eventController.close();
  });

  test(
    'partial snooze keeps only failed items and prevents hidden success',
    () async {
      ActiveRingItemsRequestDto? captured;
      final failedItem = ringItem(
        itemDeliveryId: secondDeliveryId,
        itemAttemptId: secondDeliveryAttemptId,
        itemReminderId: secondReminderId,
        itemEventId: secondEventId,
      );
      final gateway = FakeRingGateway(
        onGetState: () async => successInvocation(
          ringSnapshot(
            sequence: 1,
            sessionRevision: 1,
            activeItems: [ringItem(), failedItem],
          ),
        ),
        onSnoozeActive: (request) async {
          captured = request as ActiveRingItemsRequestDto;
          return successInvocation(
            RingSnoozeActiveResponseDto(
              results: [
                const RingSnoozeItemResultDto(
                  deliveryId: deliveryId,
                  status: RingItemActionStatus.succeeded,
                  snoozedReminderId: snoozedReminderId,
                  error: null,
                ),
                const RingSnoozeItemResultDto(
                  deliveryId: secondDeliveryId,
                  status: RingItemActionStatus.failed,
                  snoozedReminderId: null,
                  error: NativeErrorDto(
                    code: 'REMINDER_SNOOZE_NOT_ALLOWED',
                    message: 'not allowed',
                  ),
                ),
              ],
              succeededCount: 1,
              failedCount: 1,
              state: ringSnapshot(
                sequence: 2,
                sessionRevision: 2,
                activeItems: [failedItem],
              ),
            ),
          );
        },
      );
      final controller = ActiveRingSessionController(
        ringGateway: gateway,
        eventGateway: _EventDetailGateway(),
      );
      await controller.initialize();
      await controller.snoozeAll();

      expect(captured!.deliveryIds, [deliveryId, secondDeliveryId]);
      expect(controller.items.single.item.deliveryId, secondDeliveryId);
      expect(controller.notice, contains('1 项稍后提醒失败'));
      expect(controller.isActionRunning, isFalse);
      controller.dispose();
      await gateway.eventController.close();
    },
  );

  test(
    'duplicate action is ignored and stale response cannot reopen session',
    () async {
      final pending = Completer<NativeInvocation<RingStateSnapshotDto>>();
      var stopCalls = 0;
      final gateway = FakeRingGateway(
        onGetState: () async => successInvocation(
          ringSnapshot(
            sequence: 1,
            sessionRevision: 1,
            activeItems: [ringItem()],
          ),
        ),
        onStopActive: (request) {
          stopCalls += 1;
          return pending.future;
        },
      );
      final controller = ActiveRingSessionController(
        ringGateway: gateway,
        eventGateway: _EventDetailGateway(),
      );
      await controller.initialize();

      final first = controller.stopItem(deliveryId);
      final duplicate = controller.stopItem(deliveryId);
      await duplicate;
      gateway.eventController.add(
        RingStateChanged(
          RingStateChangedEventDto(
            reason: RingStateChangeReason.sessionChanged,
            state: ringSnapshot(sequence: 3, sessionRevision: 3),
          ),
        ),
      );
      pending.complete(
        successInvocation(
          ringSnapshot(
            sequence: 2,
            sessionRevision: 2,
            activeItems: [ringItem()],
          ),
        ),
      );
      await first;

      expect(stopCalls, 1);
      expect(controller.hasActiveSession, isFalse);
      expect(controller.snapshot!.sequence, 3);
      controller.dispose();
      await gateway.eventController.close();
    },
  );
}

class _EventDetailGateway implements EventNativeGateway {
  @override
  Future<NativeInvocation<EventDetailResponseDto>> getEventDetail(
    GetEventDetailRequestDto request,
  ) async {
    return successInvocation(
      EventDetailResponseDto(
        event: EventResponseDto(
          id: request.id,
          title: request.id == eventId ? '晨会' : '代码评审',
          startAt: DateTime.utc(2026, 8, 22, 8),
          endAt: DateTime.utc(2026, 8, 22, 9),
          startDate: null,
          endDate: null,
          isAllDay: false,
          hasRecurrence: false,
          status: 'active',
          recurrenceId: null,
          recurrenceRevision: null,
          timezone: 'Asia/Shanghai',
          source: 'manual',
          createdAt: DateTime.utc(2026, 8, 21),
          updatedAt: DateTime.utc(2026, 8, 21),
        ),
        recurrence: null,
        reminders: const [],
        category: null,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_request_dtos.dart';
import 'package:excellent_calendar/native_contract/ring/ring_state_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/ring_fixtures.dart';

void main() {
  test(
    'strictly parses a valid active ring state without sensitive fields',
    () {
      final rawSession = activeSessionJson(revision: 3);
      final state = RingStateSnapshotDto.fromJson(
        ringStateJson(
          sequence: 8,
          sessionRevision: 3,
          activeSession: rawSession,
        ),
      );

      expect(state.activeSession!.items.single.eventId, eventId);
      expect(state.activeSession!.phase, RingSessionPhase.audible);
      expect(rawSession['items'].toString(), isNot(contains('title')));
      expect(rawSession['items'].toString(), isNot(contains('message')));
      expect(rawSession.toString(), isNot(contains('ringtone_uri')));
    },
  );

  test(
    'rejects unknown field, enum, non-whole-second UTC, and bad version',
    () {
      expect(
        () => RingStateSnapshotDto.fromJson({
          ...ringStateJson(),
          'unexpected': true,
        }),
        throwsFormatException,
      );

      final unknownEnum = ringStateJson();
      unknownEnum['test_state'] = 'future_state';
      expect(
        () => RingStateSnapshotDto.fromJson(unknownEnum),
        throwsFormatException,
      );

      final fractionalUtc = ringStateJson();
      fractionalUtc['captured_at'] = '2026-08-22T08:00:00.000Z';
      expect(
        () => RingStateSnapshotDto.fromJson(fractionalUtc),
        throwsFormatException,
      );

      expect(
        () => NativeResultDto<RingStateSnapshotDto>.fromJson(
          {...nativeSuccess(ringStateJson()), 'contract_version': 3},
          (raw) => RingStateSnapshotDto.fromJson(raw! as Map<String, dynamic>),
        ),
        throwsFormatException,
      );
    },
  );

  test('request DTOs preserve optimistic identity and reject duplicates', () {
    final request = ActiveRingItemsRequestDto(
      runtimeInstanceId: runtimeId,
      sessionId: sessionId,
      expectedSessionRevision: 2,
      deliveryIds: [deliveryId, secondDeliveryId],
    );

    expect(request.toJson(), {
      'runtime_instance_id': runtimeId,
      'session_id': sessionId,
      'expected_session_revision': 2,
      'delivery_ids': [deliveryId, secondDeliveryId],
    });
    expect(
      () => ActiveRingItemsRequestDto(
        runtimeInstanceId: runtimeId,
        sessionId: sessionId,
        expectedSessionRevision: 2,
        deliveryIds: [deliveryId, deliveryId],
      ).toJson(),
      throwsFormatException,
    );
  });

  test('partial snooze response keeps only failed items active', () {
    final response = RingSnoozeActiveResponseDto.fromJson(
      {
        'results': [
          {
            'delivery_id': deliveryId,
            'status': 'succeeded',
            'snoozed_reminder_id': snoozedReminderId,
            'error': null,
          },
          {
            'delivery_id': secondDeliveryId,
            'status': 'failed',
            'snoozed_reminder_id': null,
            'error': {
              'code': 'REMINDER_SNOOZE_NOT_ALLOWED',
              'message': 'not allowed',
              'details': null,
              'retryable': false,
            },
          },
        ],
        'succeeded_count': 1,
        'failed_count': 1,
        'state': ringStateJson(
          sequence: 2,
          sessionRevision: 2,
          activeSession: activeSessionJson(
            revision: 2,
            items: [
              activeItemJson(
                itemDeliveryId: secondDeliveryId,
                itemAttemptId: secondDeliveryAttemptId,
                itemReminderId: secondReminderId,
                itemEventId: secondEventId,
              ),
            ],
          ),
        ),
      },
      requestedDeliveryIds: [deliveryId, secondDeliveryId],
    );

    expect(response.failedCount, 1);
    expect(
      response.state.activeSession!.items.single.deliveryId,
      secondDeliveryId,
    );
  });
}

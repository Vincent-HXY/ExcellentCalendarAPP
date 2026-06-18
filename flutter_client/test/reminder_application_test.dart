import 'dart:async';

import 'package:excellent_calendar/application/reminder/create_reminder_command.dart';
import 'package:excellent_calendar/application/reminder/create_reminder_use_case.dart';
import 'package:excellent_calendar/application/reminder/delete_reminder_command.dart';
import 'package:excellent_calendar/application/reminder/delete_reminder_use_case.dart';
import 'package:excellent_calendar/application/reminder/reminder_operation_outcome.dart';
import 'package:excellent_calendar/application/reminder/reminder_operation_state.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_contract_enums.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_reminder_gateway.dart';
import 'fixtures/reminder_fixtures.dart';

void main() {
  test(
    'create reminder succeeds and preserves request id and details',
    () async {
      final gateway = FakeReminderGateway(
        onCreate: (_) async =>
            reminderSuccessInvocation(requestId: 'native-create-1'),
        onCancel: (_) async => reminderTransportFailureInvocation(),
      );
      final phases = <ReminderOperationPhase>[];
      final useCase = CreateReminderUseCase(
        gateway,
        onStateChanged: (state) => phases.add(state.phase),
      );

      final outcome = await useCase.execute(_createCommand());

      expect(outcome.kind, ReminderOutcomeKind.success);
      expect(outcome.requestId, 'native-create-1');
      expect(
        outcome.schedulingDisposition,
        ReminderSchedulingDisposition.scheduled,
      );
      expect(phases, [
        ReminderOperationPhase.submitting,
        ReminderOperationPhase.success,
      ]);
    },
  );

  test('create reminder propagates NativeResult business failure', () async {
    final gateway = FakeReminderGateway(
      onCreate: (_) async => reminderFailureInvocation(
        code: 'REMINDER_TIME_INVALID',
        details: const {'field': 'remind_at'},
        requestId: 'native-create-failure',
      ),
      onCancel: (_) async => reminderTransportFailureInvocation(),
    );

    final outcome = await CreateReminderUseCase(
      gateway,
    ).execute(_createCommand());

    expect(outcome.kind, ReminderOutcomeKind.businessFailure);
    expect(outcome.error!.code, 'REMINDER_TIME_INVALID');
    expect(outcome.error!.details, {'field': 'remind_at'});
    expect(outcome.requestId, 'native-create-failure');
  });

  test(
    'contract validation failure is not collapsed into business failure',
    () async {
      final gateway = FakeReminderGateway(
        onCreate: (_) async => reminderFailureInvocation(
          code: 'CONTRACT_VALIDATION_FAILED',
          details: const {'field': 'methods'},
        ),
        onCancel: (_) async => reminderTransportFailureInvocation(),
      );

      final outcome = await CreateReminderUseCase(
        gateway,
      ).execute(_createCommand());

      expect(outcome.kind, ReminderOutcomeKind.contractFailure);
      expect(outcome.error!.details, {'field': 'methods'});
    },
  );

  test('create reminder expresses scheduling failed status', () async {
    final gateway = FakeReminderGateway(
      onCreate: (_) async => reminderSuccessInvocation(
        status: 'failed',
        failureReason: 'Alarm registration failed.',
      ),
      onCancel: (_) async => reminderTransportFailureInvocation(),
    );

    final outcome = await CreateReminderUseCase(
      gateway,
    ).execute(_createCommand());

    expect(outcome.kind, ReminderOutcomeKind.success);
    expect(outcome.createdButSchedulingFailed, isTrue);
    expect(outcome.reminder!.failureReason, 'Alarm registration failed.');
  });

  test(
    'delete reminder succeeds only with cancelled soft-delete state',
    () async {
      final gateway = FakeReminderGateway(
        onCreate: (_) async => reminderSuccessInvocation(),
        onCancel: (_) async => reminderSuccessInvocation(
          status: 'cancelled',
          isEnabled: false,
          deletedAt: '2026-06-15T03:00:00.000Z',
          requestId: 'native-cancel-1',
        ),
      );

      final outcome = await DeleteReminderUseCase(
        gateway,
      ).execute(_deleteCommand());

      expect(outcome.kind, ReminderOutcomeKind.success);
      expect(outcome.reminder!.status, ReminderStatus.cancelled);
      expect(outcome.reminder!.isEnabled, isFalse);
      expect(outcome.reminder!.deletedAt, isNotNull);
      expect(outcome.requestId, 'native-cancel-1');
      expect(gateway.lastCancelRequest!.toJson().keys, {'id', 'reason'});
    },
  );

  test('delete reminder propagates not found business failure', () async {
    final gateway = FakeReminderGateway(
      onCreate: (_) async => reminderSuccessInvocation(),
      onCancel: (_) async => reminderFailureInvocation(
        code: 'REMINDER_NOT_FOUND',
        details: const {'id': 'reminder-1'},
      ),
    );

    final outcome = await DeleteReminderUseCase(
      gateway,
    ).execute(_deleteCommand());

    expect(outcome.kind, ReminderOutcomeKind.businessFailure);
    expect(outcome.error!.code, 'REMINDER_NOT_FOUND');
    expect(outcome.error!.details, {'id': 'reminder-1'});
  });

  test(
    'delete reminder exposes channel failure as transport failure',
    () async {
      final gateway = FakeReminderGateway(
        onCreate: (_) async => reminderSuccessInvocation(),
        onCancel: (_) async => reminderTransportFailureInvocation(),
      );

      final outcome = await DeleteReminderUseCase(
        gateway,
      ).execute(_deleteCommand());

      expect(outcome.kind, ReminderOutcomeKind.transportFailure);
      expect(outcome.error!.details!['method'], 'reminder.cancel');
    },
  );

  test('create and same-id delete prevent duplicate submission', () async {
    final createCompleter = Completer<NativeInvocation<ReminderResponseDto>>();
    final cancelCompleter = Completer<NativeInvocation<ReminderResponseDto>>();
    final gateway = FakeReminderGateway(
      onCreate: (_) => createCompleter.future,
      onCancel: (_) => cancelCompleter.future,
    );
    final createUseCase = CreateReminderUseCase(gateway);
    final deleteUseCase = DeleteReminderUseCase(gateway);

    final firstCreate = createUseCase.execute(_createCommand());
    final duplicateCreate = await createUseCase.execute(
      _createCommand(requestId: 'local-create-2'),
    );
    expect(duplicateCreate.kind, ReminderOutcomeKind.duplicateSubmission);
    expect(gateway.createCallCount, 1);

    final firstDelete = deleteUseCase.execute(_deleteCommand());
    final duplicateDelete = await deleteUseCase.execute(
      _deleteCommand(requestId: 'local-delete-2'),
    );
    expect(duplicateDelete.kind, ReminderOutcomeKind.duplicateSubmission);
    expect(gateway.cancelCallCount, 1);

    createCompleter.complete(reminderSuccessInvocation());
    cancelCompleter.complete(
      reminderSuccessInvocation(
        status: 'cancelled',
        isEnabled: false,
        deletedAt: '2026-06-15T03:00:00.000Z',
      ),
    );
    await Future.wait([firstCreate, firstDelete]);
  });
}

CreateReminderCommand _createCommand({String requestId = 'local-create-1'}) {
  return CreateReminderCommand(
    requestId: requestId,
    targetType: ReminderTargetType.event,
    targetId: 'event-1',
    remindAt: DateTime(2026, 6, 15, 10),
    methods: const {ReminderMethod.ring},
    isEnabled: true,
    source: ReminderSource.manual,
  );
}

DeleteReminderCommand _deleteCommand({String requestId = 'local-delete-1'}) {
  return DeleteReminderCommand(
    reminderId: 'reminder-1',
    requestId: requestId,
    reason: 'User cancelled reminder.',
  );
}

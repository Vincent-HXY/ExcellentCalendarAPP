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
  // 目的：验证创建提醒成功时 Application 层输出正确阶段和结果；方法：注入成功 Fake Gateway。
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

  // 目的：确认原生业务错误原样上传；方法：Fake 返回 REMINDER_TIME_INVALID 并检查 details/requestId。
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

  // 目的：区分本地 Contract 错误与原生业务错误；方法：提交非法 methods 并检查 outcome 类型。
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

  // 目的：表示“记录创建成功但 Android 调度失败”的部分成功状态；方法：返回 failed Reminder DTO。
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

  // 目的：验证取消成功后的状态映射；方法：Fake 返回 cancelled，并检查启用与删除时间字段。
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
      expect(gateway.lastCancelRequest!.toJson(), {
        'reminder_id': 'reminder-1',
      });
    },
  );

  // 目的：确认取消不存在的提醒会保留 REMINDER_NOT_FOUND；方法：Fake 返回业务失败信封。
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

  // 目的：确认通道异常被分类为 transportFailure；方法：Fake 抛出传输错误并检查 details。
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

  // 目的：防止用户连点造成重复请求；方法：保持首个 Future 未完成并再次提交同一操作。
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
    source: ReminderSource.manual,
  );
}

DeleteReminderCommand _deleteCommand({String requestId = 'local-delete-1'}) {
  return DeleteReminderCommand(reminderId: 'reminder-1', requestId: requestId);
}

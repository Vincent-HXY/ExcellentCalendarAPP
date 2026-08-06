import '../../native_contract/common/native_error_codes.dart';
import '../../native_contract/common/native_error_dto.dart';
import '../../native_contract/reminder/reminder_contract_enums.dart';
import '../../native_contract/reminder/reminder_response_dto.dart';
import '../../native_contract/shared/native_invocation.dart';

enum ReminderOutcomeKind {
  success,
  businessFailure,
  transportFailure,
  contractFailure,
  validationFailure,
  duplicateSubmission,
}

enum ReminderSchedulingDisposition { pending, scheduled, failed, other }

abstract class ReminderOperationOutcome {
  const ReminderOperationOutcome({
    required this.kind,
    required this.operationRequestId,
    this.invocation,
    this.localMessage,
  });

  final ReminderOutcomeKind kind;
  final String operationRequestId;
  final NativeInvocation<ReminderResponseDto>? invocation;
  final String? localMessage;

  ReminderResponseDto? get reminder => invocation?.result.data;
  NativeErrorDto? get error => invocation?.result.error;
  String? get requestId => invocation?.result.requestId;
  bool get isSuccess => kind == ReminderOutcomeKind.success;
}

class CreateReminderOutcome extends ReminderOperationOutcome {
  const CreateReminderOutcome._({
    required super.kind,
    required super.operationRequestId,
    super.invocation,
    super.localMessage,
  });

  factory CreateReminderOutcome.fromInvocation({
    required String operationRequestId,
    required NativeInvocation<ReminderResponseDto> invocation,
  }) {
    return CreateReminderOutcome._(
      kind: classifyReminderInvocation(invocation),
      operationRequestId: operationRequestId,
      invocation: invocation,
    );
  }

  factory CreateReminderOutcome.validationFailure({
    required String operationRequestId,
    required String message,
  }) {
    return CreateReminderOutcome._(
      kind: ReminderOutcomeKind.validationFailure,
      operationRequestId: operationRequestId,
      localMessage: message,
    );
  }

  factory CreateReminderOutcome.duplicateSubmission(String operationRequestId) {
    return CreateReminderOutcome._(
      kind: ReminderOutcomeKind.duplicateSubmission,
      operationRequestId: operationRequestId,
      localMessage: 'A reminder create request is already submitting.',
    );
  }

  ReminderSchedulingDisposition get schedulingDisposition {
    return switch (reminder?.status) {
      ReminderStatus.pending => ReminderSchedulingDisposition.pending,
      ReminderStatus.scheduled => ReminderSchedulingDisposition.scheduled,
      ReminderStatus.failed => ReminderSchedulingDisposition.failed,
      _ => ReminderSchedulingDisposition.other,
    };
  }

  bool get createdButSchedulingFailed =>
      isSuccess &&
      schedulingDisposition == ReminderSchedulingDisposition.failed;
}

class DeleteReminderOutcome extends ReminderOperationOutcome {
  const DeleteReminderOutcome._({
    required super.kind,
    required super.operationRequestId,
    super.invocation,
    super.localMessage,
  });

  factory DeleteReminderOutcome.fromInvocation({
    required String operationRequestId,
    required NativeInvocation<ReminderResponseDto> invocation,
  }) {
    final initialKind = classifyReminderInvocation(invocation);
    if (initialKind == ReminderOutcomeKind.success) {
      final reminder = invocation.result.data!;
      final cancelled = reminder.status == ReminderStatus.cancelled;
      final disabled = !reminder.isEnabled;
      final softDeleted = reminder.deletedAt != null;
      if (!cancelled || !disabled || !softDeleted) {
        return DeleteReminderOutcome._(
          kind: ReminderOutcomeKind.contractFailure,
          operationRequestId: operationRequestId,
          invocation: invocation,
          localMessage:
              'reminder.cancel succeeded without cancelled, disabled, soft-deleted state.',
        );
      }
    }
    return DeleteReminderOutcome._(
      kind: initialKind,
      operationRequestId: operationRequestId,
      invocation: invocation,
    );
  }

  factory DeleteReminderOutcome.validationFailure({
    required String operationRequestId,
    required String message,
  }) {
    return DeleteReminderOutcome._(
      kind: ReminderOutcomeKind.validationFailure,
      operationRequestId: operationRequestId,
      localMessage: message,
    );
  }

  factory DeleteReminderOutcome.duplicateSubmission(String operationRequestId) {
    return DeleteReminderOutcome._(
      kind: ReminderOutcomeKind.duplicateSubmission,
      operationRequestId: operationRequestId,
      localMessage: 'This reminder is already being cancelled.',
    );
  }
}

ReminderOutcomeKind classifyReminderInvocation(
  NativeInvocation<ReminderResponseDto> invocation,
) {
  if (invocation.result.ok) {
    return ReminderOutcomeKind.success;
  }

  final code = invocation.result.error?.code;
  final isContractFailure =
      code == NativeErrorCodes.contractValidationFailed ||
      code == NativeErrorCodes.contractVersionUnsupported;
  if (isContractFailure) {
    return ReminderOutcomeKind.contractFailure;
  }
  if (!invocation.isNativeResult) {
    return ReminderOutcomeKind.transportFailure;
  }
  return ReminderOutcomeKind.businessFailure;
}

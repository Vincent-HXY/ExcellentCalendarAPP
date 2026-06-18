import '../../gateway_interfaces/reminder_native_gateway.dart';
import 'delete_reminder_command.dart';
import 'reminder_operation_outcome.dart';
import 'reminder_operation_state.dart';

typedef DeleteReminderStateListener =
    void Function(
      String reminderId,
      ReminderOperationState<DeleteReminderOutcome> state,
    );

class DeleteReminderUseCase {
  DeleteReminderUseCase(
    this._gateway, {
    DeleteReminderStateListener? onStateChanged,
  }) : _onStateChanged = onStateChanged;

  final ReminderNativeGateway _gateway;
  final DeleteReminderStateListener? _onStateChanged;
  final Set<String> _deletingReminderIds = {};
  final Map<String, ReminderOperationState<DeleteReminderOutcome>> _states = {};

  bool isDeleting(String reminderId) =>
      _deletingReminderIds.contains(reminderId);

  ReminderOperationState<DeleteReminderOutcome> stateFor(String reminderId) {
    return _states[reminderId] ??
        const ReminderOperationState<DeleteReminderOutcome>.idle();
  }

  Future<DeleteReminderOutcome> execute(DeleteReminderCommand command) async {
    if (_deletingReminderIds.contains(command.reminderId)) {
      return DeleteReminderOutcome.duplicateSubmission(command.requestId);
    }

    final validationMessage = command.validate();
    if (validationMessage != null) {
      final outcome = DeleteReminderOutcome.validationFailure(
        operationRequestId: command.requestId,
        message: validationMessage,
      );
      _setState(command.reminderId, ReminderOperationState.failure(outcome));
      return outcome;
    }

    _deletingReminderIds.add(command.reminderId);
    _setState(command.reminderId, const ReminderOperationState.submitting());
    try {
      final invocation = await _gateway.cancelReminder(command.toRequestDto());
      final outcome = DeleteReminderOutcome.fromInvocation(
        operationRequestId: command.requestId,
        invocation: invocation,
      );
      _setState(
        command.reminderId,
        outcome.isSuccess
            ? ReminderOperationState.success(outcome)
            : ReminderOperationState.failure(outcome),
      );
      return outcome;
    } finally {
      _deletingReminderIds.remove(command.reminderId);
    }
  }

  void _setState(
    String reminderId,
    ReminderOperationState<DeleteReminderOutcome> state,
  ) {
    _states[reminderId] = state;
    _onStateChanged?.call(reminderId, state);
  }
}

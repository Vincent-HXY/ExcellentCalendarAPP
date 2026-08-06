import '../../gateway_interfaces/reminder_native_gateway.dart';
import 'create_reminder_command.dart';
import 'reminder_operation_outcome.dart';
import 'reminder_operation_state.dart';

typedef CreateReminderStateListener =
    void Function(ReminderOperationState<CreateReminderOutcome> state);

class CreateReminderUseCase {
  CreateReminderUseCase(
    this._gateway, {
    CreateReminderStateListener? onStateChanged,
  }) : _onStateChanged = onStateChanged;

  final ReminderNativeGateway _gateway;
  final CreateReminderStateListener? _onStateChanged;

  var _isSubmitting = false;
  ReminderOperationState<CreateReminderOutcome> _state =
      const ReminderOperationState<CreateReminderOutcome>.idle();

  bool get isSubmitting => _isSubmitting;
  ReminderOperationState<CreateReminderOutcome> get state => _state;

  Future<CreateReminderOutcome> execute(CreateReminderCommand command) async {
    if (_isSubmitting) {
      return CreateReminderOutcome.duplicateSubmission(command.requestId);
    }

    final validationMessage = command.validate();
    if (validationMessage != null) {
      final outcome = CreateReminderOutcome.validationFailure(
        operationRequestId: command.requestId,
        message: validationMessage,
      );
      _setState(ReminderOperationState.failure(outcome));
      return outcome;
    }

    _isSubmitting = true;
    _setState(const ReminderOperationState.submitting());
    try {
      final invocation = await _gateway.createReminder(command.toRequestDto());
      final outcome = CreateReminderOutcome.fromInvocation(
        operationRequestId: command.requestId,
        invocation: invocation,
      );
      _setState(
        outcome.isSuccess
            ? ReminderOperationState.success(outcome)
            : ReminderOperationState.failure(outcome),
      );
      return outcome;
    } finally {
      _isSubmitting = false;
    }
  }

  void _setState(ReminderOperationState<CreateReminderOutcome> state) {
    _state = state;
    _onStateChanged?.call(state);
  }
}

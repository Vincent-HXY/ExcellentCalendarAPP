enum ReminderOperationPhase { idle, submitting, success, failure }

class ReminderOperationState<T> {
  const ReminderOperationState._({required this.phase, this.outcome});

  const ReminderOperationState.idle()
    : this._(phase: ReminderOperationPhase.idle);

  const ReminderOperationState.submitting()
    : this._(phase: ReminderOperationPhase.submitting);

  const ReminderOperationState.success(T outcome)
    : this._(phase: ReminderOperationPhase.success, outcome: outcome);

  const ReminderOperationState.failure(T outcome)
    : this._(phase: ReminderOperationPhase.failure, outcome: outcome);

  final ReminderOperationPhase phase;
  final T? outcome;
}

import '../../native_contract/common/native_error_dto.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../timezone/timezone_application_service.dart';

enum RecurringEventOccurrenceMutation { complete, reopen, skip, cancel }

enum RecurringEventSeriesMutation { complete, reopen, cancel, delete }

enum RecurringEventActionOutcome { success, failure, ignored }

class RecurringEventFailure {
  const RecurringEventFailure({
    required this.message,
    this.code,
    this.retryable = false,
  });

  factory RecurringEventFailure.fromNativeError(NativeErrorDto? error) {
    return RecurringEventFailure(
      code: error?.code,
      message: error?.message ?? '操作失败，请稍后重试',
      retryable: error?.retryable ?? false,
    );
  }

  final String? code;
  final String message;
  final bool retryable;
}

class RecurringEventActionResult {
  const RecurringEventActionResult._({
    required this.outcome,
    this.failure,
    this.warning,
  });

  const RecurringEventActionResult.success({RecurringEventFailure? warning})
    : this._(outcome: RecurringEventActionOutcome.success, warning: warning);

  const RecurringEventActionResult.failure(RecurringEventFailure failure)
    : this._(outcome: RecurringEventActionOutcome.failure, failure: failure);

  RecurringEventActionResult.ignored(String message)
    : this._(
        outcome: RecurringEventActionOutcome.ignored,
        failure: RecurringEventFailure(message: message),
      );

  final RecurringEventActionOutcome outcome;
  final RecurringEventFailure? failure;
  final RecurringEventFailure? warning;

  bool get succeeded => outcome == RecurringEventActionOutcome.success;
  bool get wasIgnored => outcome == RecurringEventActionOutcome.ignored;
}

class RecurringEventOccurrenceItem {
  const RecurringEventOccurrenceItem({
    required this.occurrence,
    required this.localizedTimeRange,
  });

  final EventOccurrenceResponseDto occurrence;
  final LocalizedTimeRange localizedTimeRange;

  String get occurrenceKey => occurrence.occurrenceKey;
  String get status => occurrence.state?.status ?? 'scheduled';
}

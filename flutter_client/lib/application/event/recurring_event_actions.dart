import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/delete_event_request_dto.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/event_occurrence_operation_request_dto.dart';
import '../../native_contract/event/event_occurrence_response_dto.dart';
import '../../native_contract/event/event_occurrence_state_response_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/event_series_operation_request_dto.dart';
import '../../native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import '../reminder/reconcile_reminder_schedule_use_case.dart';
import 'recurring_event_detail_models.dart';

class RecurringEventOccurrenceActionExecution {
  const RecurringEventOccurrenceActionExecution.success({
    required this.state,
    this.warning,
  }) : failure = null;

  const RecurringEventOccurrenceActionExecution.failure(this.failure)
    : state = null,
      warning = null;

  final EventOccurrenceStateResponseDto? state;
  final RecurringEventFailure? failure;
  final RecurringEventFailure? warning;

  bool get succeeded => state != null && failure == null;
}

class RecurringEventOccurrenceActionUseCase {
  const RecurringEventOccurrenceActionUseCase({
    required EventNativeGateway gateway,
    required ReconcileReminderScheduleUseCase reconcileUseCase,
  }) : _gateway = gateway,
       _reconcileUseCase = reconcileUseCase;

  final EventNativeGateway _gateway;
  final ReconcileReminderScheduleUseCase _reconcileUseCase;

  Future<RecurringEventOccurrenceActionExecution> execute({
    required String eventId,
    required EventDetailResponseDto detail,
    required EventOccurrenceResponseDto occurrence,
    required RecurringEventOccurrenceMutation mutation,
  }) async {
    final recurrence = detail.recurrence;
    if (recurrence == null ||
        occurrence.recurrenceRevision != recurrence.revision) {
      return const RecurringEventOccurrenceActionExecution.failure(
        RecurringEventFailure(message: '重复规则已经变化，请刷新后重试'),
      );
    }
    final request = occurrence.occurrenceStartAt != null
        ? EventOccurrenceOperationRequestDto.timed(
            eventId: eventId,
            recurrenceRevision: recurrence.revision,
            occurrenceKey: occurrence.occurrenceKey,
            occurrenceStartAt: occurrence.occurrenceStartAt!,
          )
        : EventOccurrenceOperationRequestDto.allDay(
            eventId: eventId,
            recurrenceRevision: recurrence.revision,
            occurrenceKey: occurrence.occurrenceKey,
            occurrenceStartDate: occurrence.occurrenceStartDate!,
          );
    try {
      final invocation = await switch (mutation) {
        RecurringEventOccurrenceMutation.complete =>
          _gateway.completeOccurrence(request),
        RecurringEventOccurrenceMutation.reopen => _gateway.reopenOccurrence(
          request,
        ),
        RecurringEventOccurrenceMutation.skip => _gateway.skipOccurrence(
          request,
        ),
        RecurringEventOccurrenceMutation.cancel => _gateway.cancelOccurrence(
          request,
        ),
      };
      if (!invocation.result.ok || invocation.result.data == null) {
        return RecurringEventOccurrenceActionExecution.failure(
          RecurringEventFailure.fromNativeError(invocation.result.error),
        );
      }
      final state = invocation.result.data!;
      final responseFailure = _validateResponse(state, occurrence, mutation);
      if (responseFailure != null) {
        return RecurringEventOccurrenceActionExecution.failure(responseFailure);
      }
      return RecurringEventOccurrenceActionExecution.success(
        state: state,
        warning: await _reconcileAfterMutation(_reconcileUseCase),
      );
    } catch (_) {
      return const RecurringEventOccurrenceActionExecution.failure(
        RecurringEventFailure(message: '更新 occurrence 失败，请稍后重试'),
      );
    }
  }

  static RecurringEventFailure? _validateResponse(
    EventOccurrenceStateResponseDto response,
    EventOccurrenceResponseDto occurrence,
    RecurringEventOccurrenceMutation mutation,
  ) {
    final expectedStatus = switch (mutation) {
      RecurringEventOccurrenceMutation.complete => 'completed',
      RecurringEventOccurrenceMutation.reopen => 'scheduled',
      RecurringEventOccurrenceMutation.skip => 'skipped',
      RecurringEventOccurrenceMutation.cancel => 'cancelled',
    };
    final sameStart =
        (occurrence.occurrenceStartAt != null &&
            response.occurrenceStartAt != null &&
            occurrence.occurrenceStartAt!.isAtSameMomentAs(
              response.occurrenceStartAt!,
            )) ||
        (occurrence.occurrenceStartDate != null &&
            occurrence.occurrenceStartDate == response.occurrenceStartDate);
    if (response.eventId != occurrence.eventId ||
        response.recurrenceRevision != occurrence.recurrenceRevision ||
        response.occurrenceKey != occurrence.occurrenceKey ||
        !sameStart ||
        response.status != expectedStatus) {
      return const RecurringEventFailure(
        message: 'Native occurrence 操作结果与请求不一致',
      );
    }
    return null;
  }
}

class RecurringEventSeriesActionExecution {
  const RecurringEventSeriesActionExecution.success({
    required this.event,
    required this.deleted,
    this.warning,
  }) : failure = null;

  const RecurringEventSeriesActionExecution.failure(this.failure)
    : event = null,
      deleted = false,
      warning = null;

  final EventResponseDto? event;
  final bool deleted;
  final RecurringEventFailure? failure;
  final RecurringEventFailure? warning;

  bool get succeeded => event != null && failure == null;
}

class RecurringEventSeriesActionUseCase {
  const RecurringEventSeriesActionUseCase({
    required EventNativeGateway gateway,
    required ReconcileReminderScheduleUseCase reconcileUseCase,
  }) : _gateway = gateway,
       _reconcileUseCase = reconcileUseCase;

  final EventNativeGateway _gateway;
  final ReconcileReminderScheduleUseCase _reconcileUseCase;

  Future<RecurringEventSeriesActionExecution> execute({
    required String eventId,
    required EventDetailResponseDto detail,
    required RecurringEventSeriesMutation mutation,
    String? deleteReason,
  }) async {
    final recurrence = detail.recurrence;
    if (recurrence == null) {
      return const RecurringEventSeriesActionExecution.failure(
        RecurringEventFailure(message: '该日程不是重复日程'),
      );
    }
    try {
      late final EventResponseDto event;
      if (mutation == RecurringEventSeriesMutation.delete) {
        final invocation = await _gateway.deleteEvent(
          DeleteEventRequestDto(
            id: eventId,
            deleteMode: 'soft',
            recurrenceDeleteScope: 'all_occurrences',
            expectedRecurrenceRevision: recurrence.revision,
            reason: deleteReason,
          ),
        );
        if (!invocation.result.ok || invocation.result.data == null) {
          return RecurringEventSeriesActionExecution.failure(
            RecurringEventFailure.fromNativeError(invocation.result.error),
          );
        }
        event = invocation.result.data!;
        if (!_matchesSeriesIdentity(event, detail.event) ||
            event.deletedAt == null) {
          return const RecurringEventSeriesActionExecution.failure(
            RecurringEventFailure(message: 'Native 删除结果与当前重复日程不一致'),
          );
        }
      } else {
        final request = EventSeriesOperationRequestDto(
          eventId: eventId,
          recurrenceRevision: recurrence.revision,
        );
        final invocation = await switch (mutation) {
          RecurringEventSeriesMutation.complete => _gateway.completeSeries(
            request,
          ),
          RecurringEventSeriesMutation.reopen => _gateway.reopenSeries(request),
          RecurringEventSeriesMutation.cancel => _gateway.cancelSeries(request),
          RecurringEventSeriesMutation.delete => throw StateError(
            'delete handled separately',
          ),
        };
        if (!invocation.result.ok || invocation.result.data == null) {
          return RecurringEventSeriesActionExecution.failure(
            RecurringEventFailure.fromNativeError(invocation.result.error),
          );
        }
        event = invocation.result.data!;
        final expectedStatus = switch (mutation) {
          RecurringEventSeriesMutation.complete => 'completed',
          RecurringEventSeriesMutation.reopen => 'active',
          RecurringEventSeriesMutation.cancel => 'cancelled',
          RecurringEventSeriesMutation.delete => '',
        };
        if (!_matchesSeriesIdentity(event, detail.event) ||
            event.status != expectedStatus) {
          return const RecurringEventSeriesActionExecution.failure(
            RecurringEventFailure(message: 'Native 系列操作结果与当前重复日程不一致'),
          );
        }
      }
      return RecurringEventSeriesActionExecution.success(
        event: event,
        deleted: mutation == RecurringEventSeriesMutation.delete,
        warning: await _reconcileAfterMutation(_reconcileUseCase),
      );
    } catch (_) {
      final message = mutation == RecurringEventSeriesMutation.delete
          ? '删除重复日程失败，请稍后重试'
          : '更新重复系列失败，请稍后重试';
      return RecurringEventSeriesActionExecution.failure(
        RecurringEventFailure(message: message),
      );
    }
  }

  static bool _matchesSeriesIdentity(
    EventResponseDto response,
    EventResponseDto current,
  ) {
    return response.id == current.id &&
        response.hasRecurrence &&
        response.recurrenceId == current.recurrenceId &&
        response.recurrenceRevision == current.recurrenceRevision;
  }
}

Future<RecurringEventFailure?> _reconcileAfterMutation(
  ReconcileReminderScheduleUseCase reconcileUseCase,
) async {
  try {
    final invocation = await reconcileUseCase.execute(
      triggerSource: ReminderScheduleTrigger.mutation,
      force: true,
    );
    if (!invocation.result.ok || invocation.result.data == null) {
      return RecurringEventFailure.fromNativeError(invocation.result.error);
    }
    final response = invocation.result.data!;
    if (response.failedCount > 0) {
      return RecurringEventFailure(
        message: '${response.failedCount} 条提醒暂时调度失败，稍后会继续恢复',
        retryable: true,
      );
    }
    return null;
  } catch (_) {
    return const RecurringEventFailure(
      message: '日程已更新，但提醒调度恢复失败',
      retryable: true,
    );
  }
}

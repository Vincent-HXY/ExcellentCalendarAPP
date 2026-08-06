import '../../application/event/update_event_use_case.dart';
import '../../application/timezone/timezone_application_service.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/update_event_request_dto.dart';
import '../../native_contract/recurrence/recurrence_rule_dto.dart';
import '../../native_contract/reminder/recurring_reminder_draft_request_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../../native_contract/shared/contract_field.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'new_schedule_draft.dart';

class EditRecurringEventInitialData {
  const EditRecurringEventInitialData({
    required this.startLocal,
    required this.endLocal,
    required this.recurrencePreset,
    required this.reminderAdvanceMinutes,
  });

  final DateTime startLocal;
  final DateTime endLocal;
  final RecurrencePreset recurrencePreset;
  final Set<int> reminderAdvanceMinutes;
}

class EditRecurringEventLoadResult {
  const EditRecurringEventLoadResult.success(this.data) : message = null;

  const EditRecurringEventLoadResult.failure(this.message) : data = null;

  final EditRecurringEventInitialData? data;
  final String? message;

  bool get succeeded => data != null;
}

class EditRecurringEventFormValue {
  const EditRecurringEventFormValue({
    required this.title,
    required this.note,
    required this.location,
    required this.startLocal,
    required this.endLocal,
    required this.isAllDay,
    required this.timeChanged,
    required this.recurrencePreset,
    required this.recurrenceChanged,
    required this.effectiveReminderAdvanceMinutes,
    required this.replacementReminderAdvanceMinutes,
  });

  final String title;
  final String note;
  final String location;
  final DateTime startLocal;
  final DateTime endLocal;
  final bool isAllDay;
  final bool timeChanged;
  final RecurrencePreset recurrencePreset;
  final bool recurrenceChanged;
  final Set<int> effectiveReminderAdvanceMinutes;

  /// Null keeps the existing templates. A non-null set replaces all templates.
  final Set<int>? replacementReminderAdvanceMinutes;
}

enum EditRecurringEventSubmitStatus { success, gapShifted, failure }

class EditRecurringEventSubmitResult {
  const EditRecurringEventSubmitResult._({
    required this.status,
    this.adjustedStartLocal,
    this.adjustedEndLocal,
    this.errorCode,
    this.message,
  });

  const EditRecurringEventSubmitResult.success()
    : this._(status: EditRecurringEventSubmitStatus.success);

  const EditRecurringEventSubmitResult.gapShifted({
    required DateTime adjustedStartLocal,
    required DateTime adjustedEndLocal,
  }) : this._(
         status: EditRecurringEventSubmitStatus.gapShifted,
         adjustedStartLocal: adjustedStartLocal,
         adjustedEndLocal: adjustedEndLocal,
         message: '所选时间落在夏令时跳时区间，已移到首个合法时间，请确认后再次保存',
       );

  const EditRecurringEventSubmitResult.failure({
    String? errorCode,
    required String message,
  }) : this._(
         status: EditRecurringEventSubmitStatus.failure,
         errorCode: errorCode,
         message: message,
       );

  final EditRecurringEventSubmitStatus status;
  final DateTime? adjustedStartLocal;
  final DateTime? adjustedEndLocal;
  final String? errorCode;
  final String? message;
}

/// Coordinates the recurring-series edit flow without exposing MethodChannel
/// payloads or native response maps to the page.
class EditRecurringEventController {
  const EditRecurringEventController({
    required this.detail,
    required UpdateEventUseCase updateUseCase,
    required TimezoneApplicationService timezoneService,
  }) : _updateUseCase = updateUseCase,
       _timezoneService = timezoneService;

  final EventDetailResponseDto detail;
  final UpdateEventUseCase _updateUseCase;
  final TimezoneApplicationService _timezoneService;

  Future<EditRecurringEventLoadResult> loadInitialData() async {
    final event = detail.event;
    final recurrence = detail.recurrence;
    if (!event.hasRecurrence || recurrence == null) {
      return const EditRecurringEventLoadResult.failure('该日程不是可编辑的重复系列');
    }

    final recurrencePreset = switch (recurrence.frequency) {
      'daily' => RecurrencePreset.daily,
      'weekly' => RecurrencePreset.weekly,
      'monthly' => RecurrencePreset.monthly,
      _ => null,
    };
    if (recurrencePreset == null) {
      return const EditRecurringEventLoadResult.failure('当前重复规则暂不支持编辑');
    }

    final reminderAdvanceMinutes = Set<int>.unmodifiable({
      for (final reminder in detail.reminders)
        if (reminder.recurrenceRevision == recurrence.revision &&
            reminder.advanceMinutes != null)
          reminder.advanceMinutes!,
    });

    if (event.isAllDay) {
      return EditRecurringEventLoadResult.success(
        EditRecurringEventInitialData(
          startLocal: LocalWallDateTime.fromLocalDate(
            event.startDate!,
          ).toComponentDateTime(),
          endLocal: LocalWallDateTime.fromLocalDate(
            event.endDate!,
          ).toComponentDateTime(),
          recurrencePreset: recurrencePreset,
          reminderAdvanceMinutes: reminderAdvanceMinutes,
        ),
      );
    }

    try {
      final localized = await _timezoneService.localizeEventTimes([event]);
      if (!localized.ok) {
        return EditRecurringEventLoadResult.failure(
          localized.errorMessage ?? '无法按原始时区读取日程时间',
        );
      }
      final range = localized.ranges[event.id];
      if (range == null) {
        return const EditRecurringEventLoadResult.failure('时区服务未返回日程时间');
      }
      return EditRecurringEventLoadResult.success(
        EditRecurringEventInitialData(
          startLocal: range.start.toComponentDateTime(),
          endLocal: range.end.toComponentDateTime(),
          recurrencePreset: recurrencePreset,
          reminderAdvanceMinutes: reminderAdvanceMinutes,
        ),
      );
    } on Object {
      return const EditRecurringEventLoadResult.failure('无法按原始时区读取日程时间');
    }
  }

  Future<EditRecurringEventSubmitResult> submit(
    EditRecurringEventFormValue form,
  ) async {
    final title = form.title.trim();
    if (title.isEmpty) {
      return const EditRecurringEventSubmitResult.failure(message: '请输入日程名称');
    }
    final frequency = switch (form.recurrencePreset) {
      RecurrencePreset.daily => 'daily',
      RecurrencePreset.weekly => 'weekly',
      RecurrencePreset.monthly => 'monthly',
      _ => null,
    };
    if (frequency == null) {
      return const EditRecurringEventSubmitResult.failure(
        message: '本期仅支持每天、每周或每月重复',
      );
    }
    if (form.isAllDay && form.effectiveReminderAdvanceMinutes.isNotEmpty) {
      return const EditRecurringEventSubmitResult.failure(
        message: '全天重复日程暂不支持提醒，请先清空提醒模板',
      );
    }

    DateTime? resolvedStartAt;
    DateTime? resolvedEndAt;
    String? startDate;
    String? endDate;

    try {
      if (form.timeChanged) {
        final startWall = LocalWallDateTime.fromDateTimeComponents(
          form.startLocal,
        );
        final endWall = LocalWallDateTime.fromDateTimeComponents(form.endLocal);
        if (form.isAllDay) {
          if (endWall.isBefore(startWall)) {
            return const EditRecurringEventSubmitResult.failure(
              message: '结束日期必须晚于开始日期',
            );
          }
          final start = DateTime.utc(
            form.startLocal.year,
            form.startLocal.month,
            form.startLocal.day,
          );
          var end = DateTime.utc(
            form.endLocal.year,
            form.endLocal.month,
            form.endLocal.day,
          );
          if (!end.isAfter(start)) {
            end = start.add(const Duration(days: 1));
          }
          startDate = _formatLocalDate(start);
          endDate = _formatLocalDate(end);
        } else {
          if (!startWall.isBefore(endWall)) {
            return const EditRecurringEventSubmitResult.failure(
              message: '结束时间必须晚于开始时间',
            );
          }
          final resolutions = await Future.wait([
            _timezoneApplicationResolution(startWall),
            _timezoneApplicationResolution(endWall),
          ]);
          final failed = resolutions
              .where((item) => !item.result.ok)
              .firstOrNull;
          if (failed != null) {
            final error = failed.result.error;
            return EditRecurringEventSubmitResult.failure(
              errorCode: error?.code,
              message: error?.message ?? '时区解析失败',
            );
          }
          final startResolution = resolutions[0].result.data!;
          final endResolution = resolutions[1].result.data!;
          if (startResolution.resolution ==
                  LocalDateTimeResolution.gapShifted ||
              endResolution.resolution == LocalDateTimeResolution.gapShifted) {
            return EditRecurringEventSubmitResult.gapShifted(
              adjustedStartLocal: startResolution.resolvedLocalDateTime
                  .toComponentDateTime(),
              adjustedEndLocal: endResolution.resolvedLocalDateTime
                  .toComponentDateTime(),
            );
          }
          final startInstant = startResolution.utcInstant;
          final endInstant = endResolution.utcInstant;
          if (!startInstant.isBefore(endInstant)) {
            return const EditRecurringEventSubmitResult.failure(
              message: '解析后的结束时间必须晚于开始时间',
            );
          }
          resolvedStartAt = startInstant;
          resolvedEndAt = endInstant;
        }
      }

      final reminderReplacement = form.replacementReminderAdvanceMinutes;
      final sortedReminderAdvanceMinutes = reminderReplacement?.toList()
        ?..sort();
      final request = UpdateEventRequestDto(
        id: detail.event.id,
        expectedRecurrenceRevision: detail.recurrence!.revision,
        title: title,
        content: ContractField<String>.value(
          form.note.trim().isEmpty ? null : form.note.trim(),
        ),
        location: ContractField<String>.value(
          form.location.trim().isEmpty ? null : form.location.trim(),
        ),
        startAt: form.timeChanged && !form.isAllDay ? resolvedStartAt : null,
        endAt: form.timeChanged && !form.isAllDay ? resolvedEndAt : null,
        startDate: form.timeChanged && form.isAllDay ? startDate : null,
        endDate: form.timeChanged && form.isAllDay ? endDate : null,
        isAllDay: form.timeChanged ? form.isAllDay : null,
        timezone: form.timeChanged ? detail.event.timezone : null,
        recurrence: form.recurrenceChanged
            ? ContractField<EventRecurrenceRuleInputDto>.value(
                EventRecurrenceRuleInputDto(frequency: frequency),
              )
            : const ContractField<EventRecurrenceRuleInputDto>.absent(),
        reminders: sortedReminderAdvanceMinutes
            ?.map(
              (advanceMinutes) => RecurringReminderDraftRequestDto(
                advanceMinutes: advanceMinutes,
              ),
            )
            .toList(growable: false),
      );
      request.toJson();
      final invocation = await _updateUseCase.execute(request);
      if (invocation.result.ok) {
        return const EditRecurringEventSubmitResult.success();
      }
      final error = invocation.result.error;
      return EditRecurringEventSubmitResult.failure(
        errorCode: error?.code,
        message: error?.message ?? '更新失败，请重试',
      );
    } on FormatException catch (error) {
      return EditRecurringEventSubmitResult.failure(message: error.message);
    } on Object {
      return const EditRecurringEventSubmitResult.failure(
        message: '更新失败，请稍后重试',
      );
    }
  }

  Future<NativeInvocation<ResolveLocalDateTimeResponseDto>>
  _timezoneApplicationResolution(LocalWallDateTime value) {
    return _timezoneService.resolveLocalDateTime(
      localDateTime: value,
      timezone: detail.event.timezone,
    );
  }

  static String _formatLocalDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

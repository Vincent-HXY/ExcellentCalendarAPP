import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/recurrence/recurrence_rule_dto.dart';
import '../../native_contract/reminder/reminder_draft_request_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../timezone/timezone_application_service.dart';
import 'create_event_use_case.dart';

enum CreateScheduleRecurrence { once, daily, weekly, monthly, yearly, custom }

enum CreateScheduleSubmitOutcome {
  success,
  validationFailure,
  timezoneFailure,
  gapShifted,
  nativeFailure,
  ignored,
}

class CreateScheduleDraft {
  const CreateScheduleDraft({
    required this.title,
    required this.note,
    required this.location,
    required this.start,
    required this.end,
    required this.isAllDay,
    required this.recurrence,
    required this.reminderAdvanceMinutes,
    required this.isRingingReminderEnabled,
    this.categoryId,
    this.previousTimezone,
  });

  final String title;
  final String note;
  final String location;
  final LocalWallDateTime start;
  final LocalWallDateTime end;
  final bool isAllDay;
  final CreateScheduleRecurrence recurrence;
  final List<int> reminderAdvanceMinutes;
  final bool isRingingReminderEnabled;
  final String? categoryId;
  final String? previousTimezone;
}

class CreateScheduleTimezoneResult {
  const CreateScheduleTimezoneResult.success(this.timezone)
    : errorMessage = null;

  const CreateScheduleTimezoneResult.failure(this.errorMessage)
    : timezone = null;

  final String? timezone;
  final String? errorMessage;

  bool get succeeded => timezone != null;
}

class CreateScheduleSubmitResult {
  const CreateScheduleSubmitResult._({
    required this.outcome,
    this.message,
    this.timezone,
    this.timezoneChanged = false,
    this.adjustedStart,
    this.adjustedEnd,
  });

  const CreateScheduleSubmitResult.success({
    required String timezone,
    required bool timezoneChanged,
  }) : this._(
         outcome: CreateScheduleSubmitOutcome.success,
         timezone: timezone,
         timezoneChanged: timezoneChanged,
       );

  const CreateScheduleSubmitResult.failure({
    required CreateScheduleSubmitOutcome outcome,
    required String message,
    String? timezone,
    bool timezoneChanged = false,
  }) : this._(
         outcome: outcome,
         message: message,
         timezone: timezone,
         timezoneChanged: timezoneChanged,
       );

  const CreateScheduleSubmitResult.gapShifted({
    required String timezone,
    required bool timezoneChanged,
    required LocalWallDateTime adjustedStart,
    required LocalWallDateTime adjustedEnd,
  }) : this._(
         outcome: CreateScheduleSubmitOutcome.gapShifted,
         message: '所选时间落在夏令时跳时区间，已移到首个合法时间，请确认后再次保存',
         timezone: timezone,
         timezoneChanged: timezoneChanged,
         adjustedStart: adjustedStart,
         adjustedEnd: adjustedEnd,
       );

  final CreateScheduleSubmitOutcome outcome;
  final String? message;
  final String? timezone;
  final bool timezoneChanged;
  final LocalWallDateTime? adjustedStart;
  final LocalWallDateTime? adjustedEnd;

  bool get succeeded => outcome == CreateScheduleSubmitOutcome.success;
}

class CreateScheduleController {
  CreateScheduleController({
    required CreateEventUseCase createEventUseCase,
    required TimezoneApplicationService timezoneService,
  }) : _createEventUseCase = createEventUseCase,
       _timezoneService = timezoneService;

  final CreateEventUseCase _createEventUseCase;
  final TimezoneApplicationService _timezoneService;
  bool _isSubmitting = false;

  Future<CreateScheduleTimezoneResult> refreshDeviceTimezone() async {
    final invocation = await _timezoneService.getDeviceTimezone();
    if (!invocation.result.ok || invocation.result.data == null) {
      final error = invocation.result.error;
      return CreateScheduleTimezoneResult.failure(
        error == null ? '无法读取设备时区' : '${error.code}: ${error.message}',
      );
    }
    return CreateScheduleTimezoneResult.success(
      invocation.result.data!.timezone,
    );
  }

  Future<CreateScheduleSubmitResult> submit(CreateScheduleDraft draft) async {
    if (_isSubmitting) {
      return const CreateScheduleSubmitResult.failure(
        outcome: CreateScheduleSubmitOutcome.ignored,
        message: '日程正在保存中',
      );
    }

    final validationMessage = _validate(draft);
    if (validationMessage != null) {
      return CreateScheduleSubmitResult.failure(
        outcome: CreateScheduleSubmitOutcome.validationFailure,
        message: validationMessage,
      );
    }

    _isSubmitting = true;
    try {
      final timezoneResult = await refreshDeviceTimezone();
      if (!timezoneResult.succeeded) {
        return CreateScheduleSubmitResult.failure(
          outcome: CreateScheduleSubmitOutcome.timezoneFailure,
          message: timezoneResult.errorMessage ?? '无法读取设备时区',
        );
      }
      final timezone = timezoneResult.timezone!;
      final timezoneChanged =
          draft.previousTimezone != null && draft.previousTimezone != timezone;

      DateTime? resolvedStartAt;
      DateTime? resolvedEndAt;
      if (!draft.isAllDay) {
        final resolutions = await Future.wait([
          _timezoneService.resolveLocalDateTime(
            localDateTime: draft.start,
            timezone: timezone,
          ),
          _timezoneService.resolveLocalDateTime(
            localDateTime: draft.end,
            timezone: timezone,
          ),
        ]);
        final failed = resolutions.where((item) => !item.result.ok).firstOrNull;
        if (failed != null) {
          final error = failed.result.error;
          return CreateScheduleSubmitResult.failure(
            outcome: CreateScheduleSubmitOutcome.timezoneFailure,
            message: error == null
                ? '时区解析失败'
                : '${error.code}: ${error.message}',
            timezone: timezone,
            timezoneChanged: timezoneChanged,
          );
        }
        final startResolution = resolutions[0].result.data!;
        final endResolution = resolutions[1].result.data!;
        if (startResolution.resolution == LocalDateTimeResolution.gapShifted ||
            endResolution.resolution == LocalDateTimeResolution.gapShifted) {
          return CreateScheduleSubmitResult.gapShifted(
            timezone: timezone,
            timezoneChanged: timezoneChanged,
            adjustedStart: startResolution.resolvedLocalDateTime,
            adjustedEnd: endResolution.resolvedLocalDateTime,
          );
        }
        resolvedStartAt = startResolution.utcInstant;
        resolvedEndAt = endResolution.utcInstant;
      }

      final allDayStart = DateTime.utc(
        draft.start.year,
        draft.start.month,
        draft.start.day,
      );
      final selectedAllDayEnd = DateTime.utc(
        draft.end.year,
        draft.end.month,
        draft.end.day,
      );
      final allDayEnd = selectedAllDayEnd.isAfter(allDayStart)
          ? selectedAllDayEnd
          : allDayStart.add(const Duration(days: 1));
      final methods = draft.isRingingReminderEnabled
          ? const ['popup', 'ring']
          : const ['popup'];
      final request = CreateEventRequestDto(
        title: draft.title.trim(),
        content: _optionalText(draft.note),
        startAt: resolvedStartAt,
        endAt: resolvedEndAt,
        startDate: draft.isAllDay ? _formatLocalDate(allDayStart) : null,
        endDate: draft.isAllDay ? _formatLocalDate(allDayEnd) : null,
        isAllDay: draft.isAllDay,
        categoryId: draft.categoryId,
        importance: 'unimportant_noturgent',
        location: _optionalText(draft.location),
        timezone: timezone,
        source: 'manual',
        recurrence: _recurrenceDto(draft.recurrence),
        reminders: [
          for (final advanceMinutes in draft.reminderAdvanceMinutes)
            ReminderDraftRequestDto(
              targetType: 'event',
              advanceMinutes: advanceMinutes,
              methods: methods,
              source: 'manual',
            ),
        ],
      );
      final invocation = await _createEventUseCase.execute(request);
      if (invocation.result.ok) {
        return CreateScheduleSubmitResult.success(
          timezone: timezone,
          timezoneChanged: timezoneChanged,
        );
      }
      final error = invocation.result.error;
      return CreateScheduleSubmitResult.failure(
        outcome: CreateScheduleSubmitOutcome.nativeFailure,
        message: error == null
            ? '创建失败'
            : '${error.code}: ${error.message} request_id=${invocation.result.requestId ?? '-'}',
        timezone: timezone,
        timezoneChanged: timezoneChanged,
      );
    } catch (_) {
      return const CreateScheduleSubmitResult.failure(
        outcome: CreateScheduleSubmitOutcome.nativeFailure,
        message: '创建失败，请稍后重试',
      );
    } finally {
      _isSubmitting = false;
    }
  }

  String? _validate(CreateScheduleDraft draft) {
    if (draft.title.trim().isEmpty) {
      return '请输入日程标题';
    }
    if (draft.recurrence == CreateScheduleRecurrence.yearly) {
      return '每年重复暂未开放';
    }
    if (draft.recurrence == CreateScheduleRecurrence.custom) {
      return '自定义重复规则后续实现';
    }
    final isRecurring = draft.recurrence != CreateScheduleRecurrence.once;
    if (isRecurring &&
        draft.reminderAdvanceMinutes.isNotEmpty &&
        draft.isAllDay) {
      return '全天重复日程暂不支持提醒';
    }
    if (isRecurring &&
        draft.reminderAdvanceMinutes.isNotEmpty &&
        draft.isRingingReminderEnabled) {
      return '重复日程本期仅支持弹窗提醒';
    }
    if ((!draft.isAllDay && !draft.start.isBefore(draft.end)) ||
        (draft.isAllDay && draft.end.isBefore(draft.start))) {
      return '结束时间必须晚于开始时间';
    }
    return null;
  }

  static String? _optionalText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static RecurrenceRuleDto? _recurrenceDto(
    CreateScheduleRecurrence recurrence,
  ) {
    final frequency = switch (recurrence) {
      CreateScheduleRecurrence.once => null,
      CreateScheduleRecurrence.daily => 'daily',
      CreateScheduleRecurrence.weekly => 'weekly',
      CreateScheduleRecurrence.monthly => 'monthly',
      CreateScheduleRecurrence.yearly => 'yearly',
      CreateScheduleRecurrence.custom => 'custom',
    };
    return frequency == null
        ? null
        : RecurrenceRuleDto(frequency: frequency, interval: 1);
  }

  static String _formatLocalDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-$month-$day';
  }
}

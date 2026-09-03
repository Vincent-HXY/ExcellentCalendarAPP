import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/common/native_error_codes.dart';
import '../../native_contract/recurrence/recurrence_rule_dto.dart';
import '../../native_contract/reminder/reminder_draft_request_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/ring/ring_contract_enums.dart';
import '../timezone/timezone_application_service.dart';
import 'create_event_use_case.dart';

enum CreateScheduleRecurrence { once, daily, weekly, monthly, yearly, custom }

enum CreateScheduleSubmitOutcome {
  success,
  validationFailure,
  timezoneFailure,
  gapShifted,
  nativeFailure,
  ringCapabilityFailure,
  ignored,
}

class RingCapabilityCheckResult {
  const RingCapabilityCheckResult._({
    required this.canEnable,
    required this.message,
  });

  const RingCapabilityCheckResult.available()
    : this._(canEnable: true, message: null);

  const RingCapabilityCheckResult.unavailable(String message)
    : this._(canEnable: false, message: message);

  final bool canEnable;
  final String? message;
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
    RingNativeGateway? ringGateway,
    DateTime Function()? nowProvider,
  }) : _createEventUseCase = createEventUseCase,
       _timezoneService = timezoneService,
       _ringGateway = ringGateway,
       _nowProvider = nowProvider ?? _systemNowUtc;

  final CreateEventUseCase _createEventUseCase;
  final TimezoneApplicationService _timezoneService;
  final RingNativeGateway? _ringGateway;
  final DateTime Function() _nowProvider;
  bool _isSubmitting = false;

  Future<CreateScheduleTimezoneResult> refreshDeviceTimezone() async {
    try {
      final invocation = await _timezoneService.getDeviceTimezone();
      if (!invocation.result.ok || invocation.result.data == null) {
        return CreateScheduleTimezoneResult.failure(
          _timezoneReadFailureMessage(invocation.result.error?.code),
        );
      }
      return CreateScheduleTimezoneResult.success(
        invocation.result.data!.timezone,
      );
    } catch (_) {
      return const CreateScheduleTimezoneResult.failure('无法读取设备时区，请稍后重试');
    }
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
      if (draft.isRingingReminderEnabled) {
        final capability = await checkRingCapability();
        if (!capability.canEnable) {
          return CreateScheduleSubmitResult.failure(
            outcome: CreateScheduleSubmitOutcome.ringCapabilityFailure,
            message: capability.message ?? '当前设备无法启用响铃提醒',
          );
        }
      }
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
      DateTime? allDayReminderAnchorUtc;
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
        final failed = resolutions
            .where((item) => !item.result.ok || item.result.data == null)
            .firstOrNull;
        if (failed != null) {
          return CreateScheduleSubmitResult.failure(
            outcome: CreateScheduleSubmitOutcome.timezoneFailure,
            message: _timezoneResolutionFailureMessage(
              failed.result.error?.code,
            ),
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
      } else if (draft.reminderAdvanceMinutes.isNotEmpty) {
        final invocation = await _timezoneService.resolveLocalDateTime(
          localDateTime: LocalWallDateTime(
            year: draft.start.year,
            month: draft.start.month,
            day: draft.start.day,
            hour: 0,
            minute: 0,
            second: 0,
          ),
          timezone: timezone,
        );
        if (!invocation.result.ok || invocation.result.data == null) {
          return CreateScheduleSubmitResult.failure(
            outcome: CreateScheduleSubmitOutcome.timezoneFailure,
            message: _timezoneResolutionFailureMessage(
              invocation.result.error?.code,
            ),
            timezone: timezone,
            timezoneChanged: timezoneChanged,
          );
        }
        allDayReminderAnchorUtc = invocation.result.data!.utcInstant;
      }

      if (draft.recurrence == CreateScheduleRecurrence.once &&
          draft.reminderAdvanceMinutes.isNotEmpty) {
        final reminderAnchorUtc = draft.isAllDay
            ? allDayReminderAnchorUtc!
            : resolvedStartAt!;
        final nowUtc = _nowProvider().toUtc();
        if (draft.reminderAdvanceMinutes.any(
          (advanceMinutes) => !reminderAnchorUtc
              .subtract(Duration(minutes: advanceMinutes))
              .isAfter(nowUtc),
        )) {
          return CreateScheduleSubmitResult.failure(
            outcome: CreateScheduleSubmitOutcome.validationFailure,
            message: '提醒时间已经失效，请调整日程时间或关闭提醒',
            timezone: timezone,
            timezoneChanged: timezoneChanged,
          );
        }
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
          ? const ['ring']
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
              remindAt: draft.isAllDay
                  ? allDayReminderAnchorUtc!.subtract(
                      Duration(minutes: advanceMinutes),
                    )
                  : null,
              advanceMinutes: draft.isAllDay ? null : advanceMinutes,
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
        message: _nativeFailureMessage(error?.code),
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
    if (draft.isRingingReminderEnabled && draft.isAllDay) {
      return '全天日程不支持响铃提醒';
    }
    if (draft.isRingingReminderEnabled && isRecurring) {
      return '重复日程本期仅支持弹窗提醒';
    }
    if (draft.isRingingReminderEnabled &&
        draft.reminderAdvanceMinutes.isEmpty) {
      return '请先设置提醒时间再开启响铃';
    }
    if (isRecurring &&
        draft.reminderAdvanceMinutes.isNotEmpty &&
        draft.isAllDay) {
      return '全天重复日程暂不支持提醒';
    }
    if ((!draft.isAllDay && !draft.start.isBefore(draft.end)) ||
        (draft.isAllDay && draft.end.isBefore(draft.start))) {
      return '结束时间必须晚于开始时间';
    }
    return null;
  }

  static DateTime _systemNowUtc() => DateTime.now().toUtc();

  static String _nativeFailureMessage(String? code) => switch (code) {
    NativeErrorCodes.reminderTimeInvalid => '提醒时间已经失效，请调整日程时间或关闭提醒',
    NativeErrorCodes.eventTitleEmpty => '请输入日程标题',
    NativeErrorCodes.eventTimeInvalid => '日程时间无效，请重新选择开始和结束时间',
    NativeErrorCodes.timezoneIdInvalid => '设备时区无效，请检查系统时区设置',
    NativeErrorCodes.allDayRecurringReminderNotSupported => '全天重复日程暂不支持提醒',
    _ => '创建失败，请稍后重试',
  };

  static String _timezoneReadFailureMessage(String? code) => switch (code) {
    NativeErrorCodes.timezoneIdInvalid => '设备时区无效，请检查系统时区设置',
    NativeErrorCodes.timezoneDatabaseUnavailable => '系统时区数据暂不可用，请稍后重试',
    _ => '无法读取设备时区，请稍后重试',
  };

  static String _timezoneResolutionFailureMessage(String? code) =>
      switch (code) {
        NativeErrorCodes.timezoneIdInvalid => '设备时区无效，请检查系统时区设置',
        NativeErrorCodes.timezoneDatabaseUnavailable => '系统时区数据暂不可用，请稍后重试',
        NativeErrorCodes.contractValidationFailed => '所选时间无效，请重新选择',
        _ => '无法解析所选时间，请重新选择',
      };

  static String _ringCapabilityFailureMessage(String? code) => switch (code) {
    NativeErrorCodes.notificationPermissionDenied => '通知权限不可用，请在系统设置中开启',
    NativeErrorCodes.exactAlarmPermissionDenied => '精确闹钟权限不可用，请在系统设置中开启',
    NativeErrorCodes.ringCapabilityUnavailable ||
    NativeErrorCodes.ringOutputUnavailable => '当前设备暂时无法启用响铃提醒',
    _ => '无法检查响铃能力，请稍后重试',
  };

  Future<RingCapabilityCheckResult> checkRingCapability() async {
    final gateway = _ringGateway;
    if (gateway == null) {
      return const RingCapabilityCheckResult.unavailable('响铃能力尚未连接');
    }
    try {
      final invocation = await gateway.getState();
      final state = invocation.result.data;
      if (!invocation.result.ok || state == null) {
        return RingCapabilityCheckResult.unavailable(
          _ringCapabilityFailureMessage(invocation.result.error?.code),
        );
      }
      final capability = state.capability;
      if (capability.canEnableRing) {
        return const RingCapabilityCheckResult.available();
      }
      return RingCapabilityCheckResult.unavailable(
        _blockingReasonMessage(capability.blockingReasons),
      );
    } catch (_) {
      return const RingCapabilityCheckResult.unavailable('无法检查响铃能力，请稍后重试');
    }
  }

  static String _blockingReasonMessage(
    List<RingCapabilityBlockingReason> reasons,
  ) {
    if (reasons.isEmpty) return '当前设备无法启用响铃提醒';
    final labels = reasons.map((reason) {
      return switch (reason) {
        RingCapabilityBlockingReason.notificationPermissionUnavailable =>
          '通知权限不可用',
        RingCapabilityBlockingReason.exactAlarmPermissionUnavailable =>
          '精确闹钟权限不可用',
        RingCapabilityBlockingReason.ringChannelUnavailable => '响铃通知渠道不可用',
        RingCapabilityBlockingReason.noOutputAvailable => '声音与振动均不可用',
      };
    });
    return '无法开启响铃：${labels.join('、')}';
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

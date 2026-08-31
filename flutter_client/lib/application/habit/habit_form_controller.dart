import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/bootstrap/notification_permission_controller.dart';
import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/habit/habit_request_dtos.dart';
import '../../native_contract/habit/habit_response_dtos.dart';
import '../../native_contract/shared/civil_date.dart';
import 'habit_models.dart';

enum HabitFormPhase { idle, submitting, success, failure }

class HabitFormSubmitOutcome {
  const HabitFormSubmitOutcome({
    required this.detail,
    required this.capability,
  });

  final HabitDetailResponseDto detail;
  final HabitScheduleCapabilityResponseDto capability;
  String get capabilityMessage => habitScheduleCapabilityMessage(capability);
}

enum HabitDurationPreset {
  days7,
  days21,
  days30,
  days100,
  month1,
  months3,
  year1,
  custom,
}

class HabitFormController extends ChangeNotifier {
  HabitFormController({
    required HabitGateway gateway,
    required String Function() timezoneProvider,
    HabitDetailResponseDto? initialDetail,
    NotificationPermissionController? permissionController,
    DateTime? initialStartDate,
    HabitFormSeed? seed,
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider,
       _initialDetail = initialDetail,
       _permissionController = permissionController,
       _title = initialDetail?.habit.title ?? seed?.title ?? '',
       _description =
           initialDetail?.habit.description ?? seed?.description ?? '',
       _categoryId = initialDetail?.habit.categoryId ?? seed?.categoryId,
       _quantitative =
           initialDetail?.habit.isQuantitative ?? seed?.quantitative ?? false,
       _targetText = initialDetail?.habit.targetCountHundredths == null
           ? seed?.targetText ?? ''
           : formatHundredths(initialDetail!.habit.targetCountHundredths!),
       _unit = initialDetail?.habit.unit ?? seed?.unit ?? '',
       _startDate = initialDetail == null
           ? CivilDate.fromDateTime(
               initialStartDate ?? DateTime.now(),
             ).toLocalDateTime()
           : CivilDate.parse(initialDetail.habit.startDate).toLocalDateTime(),
       _endDate = initialDetail == null
           ? CivilDate.fromDateTime(
               initialStartDate ?? DateTime.now(),
             ).addDays(29).toLocalDateTime()
           : CivilDate.parse(initialDetail.habit.endDate).toLocalDateTime(),
       _reminderEnabled = initialDetail?.reminderSettings.isEnabled ?? false,
       _reminderTime = initialDetail?.reminderSettings.template?.localTime;

  final HabitGateway _gateway;
  final String Function() _timezoneProvider;
  final HabitDetailResponseDto? _initialDetail;
  final NotificationPermissionController? _permissionController;
  String _title;
  String _description;
  String? _categoryId;
  bool _quantitative;
  String _targetText;
  String _unit;
  DateTime _startDate;
  DateTime _endDate;
  bool _reminderEnabled;
  String? _reminderTime;
  HabitFormPhase _phase = HabitFormPhase.idle;
  Map<String, String> _errors = const {};
  String? _submitError;
  String? _capabilityMessage;
  HabitScheduleCapabilityResponseDto? _actualCapability;
  bool _disposed = false;

  bool get isEditing => _initialDetail != null;
  bool get isSubmitting => _phase == HabitFormPhase.submitting;
  HabitFormPhase get phase => _phase;
  String get title => _title;
  String get description => _description;
  String? get categoryId => _categoryId;
  bool get quantitative => _quantitative;
  String get targetText => _targetText;
  String get unit => _unit;
  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;
  bool get reminderEnabled => _reminderEnabled;
  String? get reminderTime => _reminderTime;
  Map<String, String> get errors => _errors;
  String? get submitError => _submitError;
  String? get capabilityMessage => _capabilityMessage;
  HabitScheduleCapabilityResponseDto? get actualCapability => _actualCapability;
  int get plannedDays => CivilDate.fromDateTime(
    _startDate,
  ).inclusiveDaysUntil(CivilDate.fromDateTime(_endDate));
  bool get targetLocked => _initialDetail?.hasEverCheckedIn ?? false;

  void setTitle(String value) => _set(() => _title = value);
  void setDescription(String value) => _set(() => _description = value);
  void setCategoryId(String? value) => _set(() => _categoryId = value);
  void setQuantitative(bool value) {
    if (targetLocked) return;
    _set(() {
      _quantitative = value;
      if (!value) {
        _targetText = '';
        _unit = '';
      }
    });
  }

  void setTargetText(String value) {
    if (!targetLocked) _set(() => _targetText = value);
  }

  void setUnit(String value) {
    if (!targetLocked) _set(() => _unit = value);
  }

  void setStartDate(DateTime value) {
    if (targetLocked) return;
    _set(() {
      _startDate = CivilDate.fromDateTime(value).toLocalDateTime();
      if (_endDate.isBefore(_startDate)) _endDate = _startDate;
    });
  }

  void setEndDate(DateTime value) =>
      _set(() => _endDate = CivilDate.fromDateTime(value).toLocalDateTime());

  void applyPreset(HabitDurationPreset preset) {
    if (preset == HabitDurationPreset.custom) return;
    _set(() {
      _endDate = switch (preset) {
        HabitDurationPreset.days7 => CivilDate.fromDateTime(
          _startDate,
        ).addDays(6).toLocalDateTime(),
        HabitDurationPreset.days21 => CivilDate.fromDateTime(
          _startDate,
        ).addDays(20).toLocalDateTime(),
        HabitDurationPreset.days30 => CivilDate.fromDateTime(
          _startDate,
        ).addDays(29).toLocalDateTime(),
        HabitDurationPreset.days100 => CivilDate.fromDateTime(
          _startDate,
        ).addDays(99).toLocalDateTime(),
        HabitDurationPreset.month1 => CivilDate.fromDateTime(
          _startDate,
        ).addMonthsClamped(1).addDays(-1).toLocalDateTime(),
        HabitDurationPreset.months3 => CivilDate.fromDateTime(
          _startDate,
        ).addMonthsClamped(3).addDays(-1).toLocalDateTime(),
        HabitDurationPreset.year1 => CivilDate.fromDateTime(
          _startDate,
        ).addYearsClamped(1).addDays(-1).toLocalDateTime(),
        HabitDurationPreset.custom => _endDate,
      };
    });
  }

  Future<void> setReminderEnabled(bool value) async {
    if (isSubmitting || _reminderEnabled == value) return;
    _reminderEnabled = value;
    _reminderTime ??= value ? '09:00' : null;
    if (!value) _reminderTime = null;
    _notify();
    if (value && _permissionController != null) {
      final status = await _permissionController.refresh();
      if (_disposed) return;
      if (!status.succeeded) {
        _capabilityMessage = '暂时无法检查提醒权限，设置仍可保存并稍后恢复。';
      } else if (!status.status!.canPostNotifications) {
        _capabilityMessage = '通知权限未开启；提醒会保持等待授权状态。';
      } else if (!status.status!.canScheduleExactAlarms) {
        _capabilityMessage = '精确提醒不可用，将使用近似提醒。';
      } else {
        _capabilityMessage = '提醒可按精确时间调度。';
      }
      _notify();
    }
  }

  void setReminderTime(String value) {
    if (_reminderEnabled) _set(() => _reminderTime = value);
  }

  Future<HabitFormSubmitOutcome?> submit() async {
    if (isSubmitting || !_validate()) return null;
    _phase = HabitFormPhase.submitting;
    _submitError = null;
    _notify();
    final target = _quantitative ? parseHundredths(_targetText) : null;
    final reminder = _reminderEnabled
        ? HabitReminderPlanInputDto.enabled(_reminderTime)
        : const HabitReminderPlanInputDto.disabled();
    try {
      final result = isEditing
          ? await _gateway.update(
              UpdateHabitRequestDto(
                id: _initialDetail!.habit.id,
                expectedUpdatedAt: _initialDetail.habit.updatedAt,
                title: _title.trim(),
                description: _nullableTrimmed(_description),
                categoryId: _categoryId,
                targetCountHundredths: target,
                unit: _quantitative ? _unit.trim() : null,
                startDate: _formatDate(_startDate),
                endDate: _formatDate(_endDate),
                timezone: _timezoneProvider(),
                reminder: reminder,
                replaceReminder: true,
              ),
            )
          : await _gateway.create(
              CreateHabitRequestDto(
                title: _title.trim(),
                description: _nullableTrimmed(_description),
                categoryId: _categoryId,
                targetCountHundredths: target,
                unit: _quantitative ? _unit.trim() : null,
                startDate: _formatDate(_startDate),
                endDate: _formatDate(_endDate),
                reminder: reminder,
                timezone: _timezoneProvider(),
              ),
            );
      if (_disposed) return null;
      _phase = HabitFormPhase.success;
      _actualCapability = result.capability;
      _capabilityMessage = habitScheduleCapabilityMessage(result.capability);
      _notify();
      return HabitFormSubmitOutcome(
        detail: result.detail,
        capability: result.capability,
      );
    } catch (error) {
      if (_disposed) return null;
      _phase = HabitFormPhase.failure;
      _submitError = habitFailureMessage(error);
      _notify();
      return null;
    }
  }

  HabitFormSeed restartSeed() => HabitFormSeed(
    title: _title,
    description: _description,
    categoryId: _categoryId,
    quantitative: _quantitative,
    targetText: _targetText,
    unit: _unit,
  );

  bool _validate() {
    final errors = <String, String>{};
    final title = _title.trim();
    if (title.isEmpty) {
      errors['title'] = '请输入习惯名称';
    } else if (title.runes.length > 80) {
      errors['title'] = '习惯名称不能超过 80 个字符';
    }
    if (_description.runes.length > 2000) {
      errors['description'] = '描述不能超过 2000 个字符';
    }
    if (_quantitative) {
      try {
        final quantity = parseHundredths(_targetText);
        if (quantity == null || quantity <= 0) {
          errors['target'] = '目标数量必须大于 0';
        }
      } on FormatException {
        errors['target'] = '请输入最多两位小数的有效数量';
      }
      if (_unit.trim().isEmpty) {
        errors['unit'] = '请输入单位';
      } else if (_unit.trim().runes.length > 32) {
        errors['unit'] = '单位不能超过 32 个字符';
      }
    }
    if (_endDate.isBefore(_startDate)) {
      errors['dates'] = '结束日期不能早于开始日期';
    } else if (plannedDays > 400) {
      errors['dates'] = '挑战期限不能超过 400 天';
    }
    if (_initialDetail != null) {
      final latest = _initialDetail.latestCheckInDate;
      final today = CivilDate.fromDateTime(DateTime.now()).toLocalDateTime();
      if (_endDate.isBefore(today) ||
          (latest != null && _endDate.isBefore(DateTime.parse(latest)))) {
        errors['dates'] = '结束日期不能早于今天或已有打卡日期';
      }
    }
    if (_reminderEnabled &&
        (_reminderTime == null ||
            !RegExp(
              r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$',
            ).hasMatch(_reminderTime!))) {
      errors['reminder'] = '请选择有效提醒时间';
    }
    _errors = Map.unmodifiable(errors);
    _submitError = null;
    _notify();
    return errors.isEmpty;
  }

  void _set(VoidCallback update) {
    if (isSubmitting) return;
    update();
    _phase = HabitFormPhase.idle;
    _submitError = null;
    _errors = const {};
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class HabitFormSeed {
  const HabitFormSeed({
    required this.title,
    required this.description,
    required this.categoryId,
    required this.quantitative,
    required this.targetText,
    required this.unit,
  });
  final String title;
  final String description;
  final String? categoryId;
  final bool quantitative;
  final String targetText;
  final String unit;
}

int? parseHundredths(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Quantity must be an exact decimal string.');
  }
  final parts = value.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  if (whole > 90071992547409) {
    throw const FormatException('Quantity exceeds safe-integer hundredths.');
  }
  final result = whole * 100 + fraction;
  if (result > 9007199254740991) {
    throw const FormatException('Quantity exceeds safe-integer hundredths.');
  }
  return result;
}

String _formatDate(DateTime value) => CivilDate.fromDateTime(value).format();
String? _nullableTrimmed(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

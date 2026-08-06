import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/event/create_event_use_case.dart';
import '../../application/timezone/timezone_application_service.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../../native_contract/runtime/resolve_local_datetime_dto.dart';
import 'components/create_mode_segmented_control.dart';
import 'components/manual_schedule_form.dart';
import 'components/new_schedule_top_bar.dart';
import 'date_time_picker/schedule_date_time_picker.dart';
import 'new_schedule_draft.dart';
import 'new_schedule_design_tokens.dart';
import 'schedule_submit_controller.dart';
import 'selection/recurrence_selection_sheet.dart';
import 'selection/reminder_selection_sheet.dart';

enum CreateScheduleMode { manual, aiRecognition }

class NewSchedulePage extends StatefulWidget {
  const NewSchedulePage({
    required this.createUseCase,
    required this.timezoneService,
    super.key,
  });

  final CreateEventUseCase createUseCase;
  final TimezoneApplicationService timezoneService;

  @override
  State<NewSchedulePage> createState() => _NewSchedulePageState();
}

class _NewSchedulePageState extends State<NewSchedulePage> {
  late final ScheduleSubmitController _submitController;
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();

  CreateScheduleMode _mode = CreateScheduleMode.manual;
  bool _isAllDay = false;
  bool _isRingingReminderEnabled = false;
  bool _isMoreSettingsExpanded = true;
  bool _isSubmitting = false;
  RecurrencePreset _recurrencePreset = RecurrencePreset.once;
  Set<ReminderPreset> _reminderPresets = {ReminderPreset.minutes15};
  int? _customReminderAdvanceMinutes;

  late DateTime _startAt;
  late DateTime _endAt;
  String? _timezoneId;

  String get _timezoneLabel => _timezoneId ?? '正在读取设备时区…';

  @override
  void initState() {
    super.initState();
    _submitController = ScheduleSubmitController(widget.createUseCase);
    _startAt = _nextDefaultStartAt();
    _endAt = _startAt.add(const Duration(hours: 1));
    _titleController.addListener(_handleTitleChanged);
    unawaited(_refreshDeviceTimezone(showError: true));
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _handleTitleChanged() {
    setState(() {});
  }

  static DateTime _nextDefaultStartAt() {
    final now = DateTime.now();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(const Duration(hours: 1));
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty && !_isSubmitting;

  bool get _isRecurring => _recurrencePreset != RecurrencePreset.once;

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _isSubmitting) {
      return;
    }

    if (_isRecurring && _reminderPresets.isNotEmpty && _isAllDay) {
      _showTodo('全天重复日程暂不支持提醒');
      return;
    }
    if (_isRecurring &&
        _reminderPresets.isNotEmpty &&
        _isRingingReminderEnabled) {
      _showTodo('重复日程本期仅支持弹窗提醒');
      return;
    }

    final startWall = LocalWallDateTime.fromDateTimeComponents(_startAt);
    final endWall = LocalWallDateTime.fromDateTimeComponents(_endAt);
    if ((!_isAllDay && !startWall.isBefore(endWall)) ||
        (_isAllDay && endWall.isBefore(startWall))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final previousTimezone = _timezoneId;
    final timezone = await _refreshDeviceTimezone(showError: true);
    if (!mounted) return;
    if (timezone == null) {
      setState(() {
        _isSubmitting = false;
      });
      return;
    }
    if (previousTimezone != null && previousTimezone != timezone) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('设备时区已切换为 $timezone，将按新时区保存')));
    }

    DateTime? resolvedStartAt;
    DateTime? resolvedEndAt;
    if (!_isAllDay) {
      final resolutions = await Future.wait([
        widget.timezoneService.resolveLocalDateTime(
          localDateTime: startWall,
          timezone: timezone,
        ),
        widget.timezoneService.resolveLocalDateTime(
          localDateTime: endWall,
          timezone: timezone,
        ),
      ]);
      if (!mounted) return;
      final failed = resolutions.where((item) => !item.result.ok).firstOrNull;
      if (failed != null) {
        setState(() {
          _isSubmitting = false;
        });
        final error = failed.result.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error == null ? '时区解析失败' : '${error.code}: ${error.message}',
            ),
          ),
        );
        return;
      }
      final startResolution = resolutions[0].result.data!;
      final endResolution = resolutions[1].result.data!;
      if (startResolution.resolution == LocalDateTimeResolution.gapShifted ||
          endResolution.resolution == LocalDateTimeResolution.gapShifted) {
        setState(() {
          _startAt = startResolution.resolvedLocalDateTime
              .toComponentDateTime();
          _endAt = endResolution.resolvedLocalDateTime.toComponentDateTime();
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选时间落在夏令时跳时区间，已移到首个合法时间，请确认后再次保存')),
        );
        return;
      }
      resolvedStartAt = startResolution.utcInstant;
      resolvedEndAt = endResolution.utcInstant;
    }

    final note = _noteController.text.trim();
    final location = _locationController.text.trim();
    final allDayStart = DateTime(_startAt.year, _startAt.month, _startAt.day);
    final selectedAllDayEnd = DateTime(_endAt.year, _endAt.month, _endAt.day);
    final allDayEnd = selectedAllDayEnd.isAfter(allDayStart)
        ? selectedAllDayEnd
        : allDayStart.add(const Duration(days: 1));
    final request = CreateEventRequestDto(
      title: title,
      content: note.isEmpty ? null : note,
      startAt: resolvedStartAt,
      endAt: resolvedEndAt,
      startDate: _isAllDay ? _formatLocalDate(allDayStart) : null,
      endDate: _isAllDay ? _formatLocalDate(allDayEnd) : null,
      isAllDay: _isAllDay,
      categoryId: '1',
      importance: 'unimportant_noturgent',
      location: location.isEmpty ? null : location,
      timezone: timezone,
      source: 'manual',
      recurrence: _recurrencePreset.toDto(),
      reminders: buildReminderDraftDtos(
        presets: _reminderPresets,
        customAdvanceMinutes: _customReminderAdvanceMinutes,
        isRingingEnabled: _isRingingReminderEnabled,
      ),
    );

    final invocation = await _submitController.submit(request);
    if (!mounted) {
      return;
    }

    if (invocation.result.ok) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSubmitting = false;
    });
    final error = invocation.result.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? '创建失败'
              : '${error.code}: ${error.message} request_id=${invocation.result.requestId ?? '-'}',
        ),
      ),
    );
  }

  static String _formatLocalDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-$month-$day';
  }

  Future<String?> _refreshDeviceTimezone({required bool showError}) async {
    final invocation = await widget.timezoneService.getDeviceTimezone();
    if (!mounted) return null;
    if (!invocation.result.ok) {
      if (showError) {
        final error = invocation.result.error;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error == null ? '无法读取设备时区' : '${error.code}: ${error.message}',
            ),
          ),
        );
      }
      return null;
    }
    final timezone = invocation.result.data!.timezone;
    if (_timezoneId != timezone) {
      setState(() {
        _timezoneId = timezone;
      });
    }
    return timezone;
  }

  void _showTodo(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickStartDateTime(PickerInitialStep initialStep) async {
    final result = await showScheduleDateTimePicker(
      context: context,
      initialDateTime: _startAt,
      timezone: _timezoneLabel,
      initialStep: initialStep,
      target: PickerTarget.start,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _startAt = DateTime.utc(
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
      );
    });
  }

  Future<void> _pickEndDateTime(PickerInitialStep initialStep) async {
    final result = await showScheduleDateTimePicker(
      context: context,
      initialDateTime: _endAt,
      timezone: _timezoneLabel,
      initialStep: initialStep,
      target: PickerTarget.end,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _endAt = DateTime.utc(
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
      );
    });
  }

  Future<void> _pickRecurrence() async {
    final result = await showRecurrenceSelectionSheet(
      context: context,
      initialValue: _recurrencePreset,
      onUnsupported: (preset) => _showTodo(
        preset == RecurrencePreset.yearly ? '每年重复暂未开放' : '自定义重复规则后续实现',
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    if (result != RecurrencePreset.once &&
        _isAllDay &&
        _reminderPresets.isNotEmpty) {
      _showTodo('全天重复日程暂不支持提醒');
      return;
    }
    if (result != RecurrencePreset.once && _isRingingReminderEnabled) {
      _showTodo('重复日程本期仅支持弹窗提醒');
      return;
    }
    setState(() {
      _recurrencePreset = result;
    });
  }

  Future<void> _pickReminders() async {
    if (_isRecurring && _isAllDay) {
      _showTodo('全天重复日程暂不支持提醒');
      return;
    }
    if (_isRecurring && _isRingingReminderEnabled) {
      _showTodo('重复日程本期仅支持弹窗提醒');
      return;
    }
    final result = await showReminderSelectionSheet(
      context: context,
      initialPresets: _reminderPresets,
      initialCustomAdvanceMinutes: _customReminderAdvanceMinutes,
      onRemainingTenPercentUnsupported: () => _showTodo('剩余 10% 提醒后续实现'),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _reminderPresets = result.presets;
      _customReminderAdvanceMinutes = result.customAdvanceMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NewScheduleColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            NewScheduleTopBar(
              canSubmit: _canSubmit,
              isSubmitting: _isSubmitting,
              onCancel: () => Navigator.of(context).pop(false),
              onSubmit: _handleSubmit,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NewScheduleSpacing.pageHorizontal,
                  8,
                  NewScheduleSpacing.pageHorizontal,
                  NewScheduleSpacing.bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreateModeSegmentedControl(
                      selectedMode: _mode,
                      onChanged: (mode) {
                        setState(() {
                          _mode = mode;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_mode == CreateScheduleMode.manual)
                      ManualScheduleForm(
                        titleController: _titleController,
                        noteController: _noteController,
                        locationController: _locationController,
                        startAt: _startAt,
                        endAt: _endAt,
                        isAllDay: _isAllDay,
                        isRingingReminderEnabled: _isRingingReminderEnabled,
                        isMoreSettingsExpanded: _isMoreSettingsExpanded,
                        recurrenceLabel: _recurrencePreset.label,
                        reminderSummary: reminderSummary(
                          presets: _reminderPresets,
                          customAdvanceMinutes: _customReminderAdvanceMinutes,
                        ),
                        timezoneLabel: _timezoneLabel,
                        onAllDayChanged: (value) {
                          if (value &&
                              _isRecurring &&
                              _reminderPresets.isNotEmpty) {
                            _showTodo('全天重复日程暂不支持提醒');
                            return;
                          }
                          setState(() {
                            _isAllDay = value;
                          });
                        },
                        onRingingReminderChanged: (value) {
                          if (value && _isRecurring) {
                            _showTodo('重复日程本期仅支持弹窗提醒');
                            return;
                          }
                          setState(() {
                            _isRingingReminderEnabled = value;
                          });
                        },
                        onMoreSettingsToggle: () {
                          setState(() {
                            _isMoreSettingsExpanded = !_isMoreSettingsExpanded;
                          });
                        },
                        onStartTap: () =>
                            _pickStartDateTime(PickerInitialStep.calendar),
                        onStartTimeTap: () =>
                            _pickStartDateTime(PickerInitialStep.time),
                        onStartDateTap: () =>
                            _pickStartDateTime(PickerInitialStep.calendar),
                        onEndTap: () =>
                            _pickEndDateTime(PickerInitialStep.calendar),
                        onEndTimeTap: () =>
                            _pickEndDateTime(PickerInitialStep.time),
                        onEndDateTap: () =>
                            _pickEndDateTime(PickerInitialStep.calendar),
                        onRecurrenceTap: _pickRecurrence,
                        onReminderTap: _pickReminders,
                        onLocationMapTap: () => _showTodo('地图选择功能后续实现'),
                        onTodoTap: _showTodo,
                      )
                    else
                      const _RecognitionPlaceholder(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecognitionPlaceholder extends StatelessWidget {
  const _RecognitionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: NewScheduleColors.surface,
        borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
      ),
      child: const Center(
        child: Text('后续支持图片 / 文本智能识别', style: NewScheduleTextStyles.rowValue),
      ),
    );
  }
}

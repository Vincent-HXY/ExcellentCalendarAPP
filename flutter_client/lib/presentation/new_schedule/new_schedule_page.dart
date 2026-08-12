import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/category/category_models.dart';
import '../../application/event/create_schedule_controller.dart';
import '../../application/event/create_event_use_case.dart';
import '../../application/timezone/timezone_application_service.dart';
import '../../gateway_interfaces/category_repository.dart';
import '../../native_contract/runtime/local_wall_date_time.dart';
import '../category/category_picker_page.dart';
import '../category/category_picker_result.dart';
import 'components/create_mode_segmented_control.dart';
import 'components/manual_schedule_form.dart';
import 'components/new_schedule_top_bar.dart';
import 'date_time_picker/schedule_date_time_picker.dart';
import 'new_schedule_draft.dart';
import 'new_schedule_design_tokens.dart';
import 'selection/recurrence_selection_sheet.dart';
import 'selection/reminder_selection_sheet.dart';

enum CreateScheduleMode { manual, aiRecognition }

class NewSchedulePage extends StatefulWidget {
  const NewSchedulePage({
    required this.createUseCase,
    required this.timezoneService,
    required this.categoryRepository,
    super.key,
  });

  final CreateEventUseCase createUseCase;
  final TimezoneApplicationService timezoneService;
  final CategoryRepository categoryRepository;

  @override
  State<NewSchedulePage> createState() => _NewSchedulePageState();
}

class _NewSchedulePageState extends State<NewSchedulePage> {
  late final CreateScheduleController _submitController;
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
  Category? _selectedCategory;

  late DateTime _startAt;
  late DateTime _endAt;
  String? _timezoneId;

  String get _timezoneLabel => _timezoneId ?? '正在读取设备时区…';

  @override
  void initState() {
    super.initState();
    _submitController = CreateScheduleController(
      createEventUseCase: widget.createUseCase,
      timezoneService: widget.timezoneService,
    );
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

  String get _categoryLabel {
    final selected = _selectedCategory;
    if (selected != null) {
      return selected.name;
    }
    return '未分类';
  }

  Future<void> _pickCategory() async {
    final result = await Navigator.of(context).push<CategoryPickerResult>(
      MaterialPageRoute<CategoryPickerResult>(
        builder: (_) => CategoryPickerPage(
          repository: widget.categoryRepository,
          selectedCategoryId: _selectedCategory?.id,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _selectedCategory = result.category;
    });
  }

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });
    final result = await _submitController.submit(
      CreateScheduleDraft(
        title: title,
        note: _noteController.text,
        location: _locationController.text,
        start: LocalWallDateTime.fromDateTimeComponents(_startAt),
        end: LocalWallDateTime.fromDateTimeComponents(_endAt),
        isAllDay: _isAllDay,
        recurrence: _applicationRecurrence(_recurrencePreset),
        reminderAdvanceMinutes: selectedReminderAdvanceMinutes(
          presets: _reminderPresets,
          customAdvanceMinutes: _customReminderAdvanceMinutes,
        ),
        isRingingReminderEnabled: _isRingingReminderEnabled,
        categoryId: _selectedCategory?.id,
        previousTimezone: _timezoneId,
      ),
    );
    if (!mounted) {
      return;
    }
    final timezone = result.timezone;
    if (timezone != null && _timezoneId != timezone) {
      setState(() {
        _timezoneId = timezone;
      });
    }
    if (result.timezoneChanged && timezone != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('设备时区已切换为 $timezone，将按新时区保存')));
    }
    if (result.succeeded) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      if (result.outcome == CreateScheduleSubmitOutcome.gapShifted) {
        _startAt = result.adjustedStart!.toComponentDateTime();
        _endAt = result.adjustedEnd!.toComponentDateTime();
      }
      _isSubmitting = false;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message ?? '创建失败')));
  }

  static CreateScheduleRecurrence _applicationRecurrence(
    RecurrencePreset recurrence,
  ) {
    return switch (recurrence) {
      RecurrencePreset.once => CreateScheduleRecurrence.once,
      RecurrencePreset.daily => CreateScheduleRecurrence.daily,
      RecurrencePreset.weekly => CreateScheduleRecurrence.weekly,
      RecurrencePreset.monthly => CreateScheduleRecurrence.monthly,
      RecurrencePreset.yearly => CreateScheduleRecurrence.yearly,
      RecurrencePreset.custom => CreateScheduleRecurrence.custom,
    };
  }

  Future<String?> _refreshDeviceTimezone({required bool showError}) async {
    final result = await _submitController.refreshDeviceTimezone();
    if (!mounted) return null;
    if (!result.succeeded) {
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage ?? '无法读取设备时区')),
        );
      }
      return null;
    }
    final timezone = result.timezone!;
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
                        categoryLabel: _categoryLabel,
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
                        onCategoryTap: _pickCategory,
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

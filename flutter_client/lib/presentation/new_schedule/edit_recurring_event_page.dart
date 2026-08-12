import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/event/update_event_use_case.dart';
import '../../application/timezone/timezone_application_service.dart';
import '../../gateway_interfaces/category_repository.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../category/category_picker_page.dart';
import '../category/category_picker_result.dart';
import 'components/manual_schedule_form.dart';
import 'date_time_picker/schedule_date_time_picker.dart';
import 'edit_recurring_event_controller.dart';
import 'new_schedule_design_tokens.dart';
import 'new_schedule_draft.dart';
import 'selection/recurrence_selection_sheet.dart';
import 'selection/reminder_selection_sheet.dart';

class EditRecurringEventPage extends StatefulWidget {
  const EditRecurringEventPage({
    required this.detail,
    required this.updateUseCase,
    required this.timezoneService,
    required this.categoryRepository,
    super.key,
  });

  final EventDetailResponseDto detail;
  final UpdateEventUseCase updateUseCase;
  final TimezoneApplicationService timezoneService;
  final CategoryRepository categoryRepository;

  @override
  State<EditRecurringEventPage> createState() => _EditRecurringEventPageState();
}

class _EditRecurringEventPageState extends State<EditRecurringEventPage> {
  late final EditRecurringEventController _editController;
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _locationController;

  bool _isInitializing = true;
  bool _isSubmitting = false;
  bool _isAllDay = false;
  bool _isMoreSettingsExpanded = true;
  bool _timeChanged = false;
  bool _recurrenceChanged = false;
  bool _remindersChanged = false;
  bool _categoryChanged = false;
  String? _initializationError;
  int _loadGeneration = 0;

  late DateTime _startLocal;
  late DateTime _endLocal;
  late RecurrencePreset _initialRecurrencePreset;
  RecurrencePreset _recurrencePreset = RecurrencePreset.daily;
  Set<ReminderPreset> _reminderPresets = {};
  int? _customReminderAdvanceMinutes;
  Set<int> _additionalCustomAdvanceMinutes = {};
  Set<int> _initialReminderAdvanceMinutes = {};
  String? _selectedCategoryId;
  String _selectedCategoryName = '未分类';

  @override
  void initState() {
    super.initState();
    final event = widget.detail.event;
    _editController = EditRecurringEventController(
      detail: widget.detail,
      updateUseCase: widget.updateUseCase,
      timezoneService: widget.timezoneService,
    );
    _titleController = TextEditingController(text: event.title);
    _noteController = TextEditingController(text: event.content ?? '');
    _locationController = TextEditingController(text: event.location ?? '');
    _selectedCategoryId = event.categoryId;
    _selectedCategoryName = event.categoryId == null
        ? '未分类'
        : widget.detail.category?.name ?? '分类不可用或已删除';
    _isAllDay = event.isAllDay;
    _titleController.addListener(_handleTitleChanged);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_isInitializing &&
      !_isSubmitting &&
      _initializationError == null &&
      _titleController.text.trim().isNotEmpty;

  Set<int> get _effectiveReminderAdvanceMinutes {
    final values = <int>{..._additionalCustomAdvanceMinutes};
    for (final preset in _reminderPresets) {
      if (preset == ReminderPreset.custom) {
        if (_customReminderAdvanceMinutes != null) {
          values.add(_customReminderAdvanceMinutes!);
        }
      } else {
        final fixedValue = preset.fixedAdvanceMinutes;
        if (fixedValue != null) values.add(fixedValue);
      }
    }
    return values;
  }

  String get _reminderSummary {
    if (_additionalCustomAdvanceMinutes.isNotEmpty) {
      final count = _effectiveReminderAdvanceMinutes.length;
      return count == 1
          ? formatReminderAdvanceMinutes(
              _effectiveReminderAdvanceMinutes.single,
            )
          : '已设置 $count 个提醒';
    }
    return reminderSummary(
      presets: _reminderPresets,
      customAdvanceMinutes: _customReminderAdvanceMinutes,
    );
  }

  void _handleTitleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    final generation = ++_loadGeneration;
    setState(() {
      _isInitializing = true;
      _initializationError = null;
    });
    final result = await _editController.loadInitialData();
    if (!mounted || generation != _loadGeneration) return;
    if (!result.succeeded) {
      setState(() {
        _isInitializing = false;
        _initializationError = result.message ?? '加载失败';
      });
      return;
    }
    final data = result.data!;
    setState(() {
      _startLocal = data.startLocal;
      _endLocal = data.endLocal;
      _initialRecurrencePreset = data.recurrencePreset;
      _recurrencePreset = data.recurrencePreset;
      _initialReminderAdvanceMinutes = {...data.reminderAdvanceMinutes};
      _applyReminderAdvanceMinutes(data.reminderAdvanceMinutes);
      _isInitializing = false;
      _initializationError = null;
    });
  }

  void _applyReminderAdvanceMinutes(Set<int> advanceMinutes) {
    _reminderPresets = {};
    _customReminderAdvanceMinutes = null;
    _additionalCustomAdvanceMinutes = {};
    for (final advance in advanceMinutes.toList()..sort()) {
      final preset = _presetForAdvanceMinutes(advance);
      if (preset != null) {
        _reminderPresets.add(preset);
      } else if (_customReminderAdvanceMinutes == null) {
        _customReminderAdvanceMinutes = advance;
        _reminderPresets.add(ReminderPreset.custom);
      } else {
        _additionalCustomAdvanceMinutes.add(advance);
      }
    }
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
    });
    final result = await _editController.submit(
      EditRecurringEventFormValue(
        title: _titleController.text,
        note: _noteController.text,
        location: _locationController.text,
        startLocal: _startLocal,
        endLocal: _endLocal,
        isAllDay: _isAllDay,
        timeChanged: _timeChanged,
        recurrencePreset: _recurrencePreset,
        recurrenceChanged: _recurrenceChanged,
        categoryId: _selectedCategoryId,
        categoryChanged: _categoryChanged,
        effectiveReminderAdvanceMinutes: _effectiveReminderAdvanceMinutes,
        replacementReminderAdvanceMinutes: _remindersChanged
            ? _effectiveReminderAdvanceMinutes
            : null,
      ),
    );
    if (!mounted) return;
    switch (result.status) {
      case EditRecurringEventSubmitStatus.success:
        Navigator.of(context).pop(true);
        return;
      case EditRecurringEventSubmitStatus.gapShifted:
        setState(() {
          _startLocal = result.adjustedStartLocal!;
          _endLocal = result.adjustedEndLocal!;
          _timeChanged = true;
          _isSubmitting = false;
        });
        _showMessage(result.message!);
      case EditRecurringEventSubmitStatus.failure:
        setState(() {
          _isSubmitting = false;
        });
        _showMessage(
          result.errorCode == null
              ? result.message!
              : '${result.errorCode}: ${result.message}',
        );
    }
  }

  Future<void> _pickStartDateTime(PickerInitialStep initialStep) async {
    final result = await showScheduleDateTimePicker(
      context: context,
      initialDateTime: _startLocal,
      timezone: widget.detail.event.timezone,
      initialStep: initialStep,
      target: PickerTarget.start,
    );
    if (result == null || !mounted) return;
    setState(() {
      _startLocal = DateTime.utc(
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
      );
      _timeChanged = true;
    });
  }

  Future<void> _pickEndDateTime(PickerInitialStep initialStep) async {
    final result = await showScheduleDateTimePicker(
      context: context,
      initialDateTime: _endLocal,
      timezone: widget.detail.event.timezone,
      initialStep: initialStep,
      target: PickerTarget.end,
    );
    if (result == null || !mounted) return;
    setState(() {
      _endLocal = DateTime.utc(
        result.year,
        result.month,
        result.day,
        result.hour,
        result.minute,
      );
      _timeChanged = true;
    });
  }

  Future<void> _pickRecurrence() async {
    final result = await showRecurrenceSelectionSheet(
      context: context,
      initialValue: _recurrencePreset,
      onUnsupported: (preset) => _showMessage(
        preset == RecurrencePreset.yearly ? '每年重复暂未开放' : '自定义重复规则暂未开放',
      ),
    );
    if (result == null || !mounted) return;
    if (result == RecurrencePreset.once) {
      _showMessage('重复系列本期不能改为仅一次日程');
      return;
    }
    setState(() {
      _recurrencePreset = result;
      _recurrenceChanged = result != _initialRecurrencePreset;
    });
  }

  Future<void> _pickReminders() async {
    if (_isAllDay) {
      _showMessage('全天重复日程暂不支持提醒');
      return;
    }
    if (_additionalCustomAdvanceMinutes.isNotEmpty) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('替换提醒模板？'),
          content: Text(
            '当前系列包含多个自定义提醒（${_effectiveReminderAdvanceMinutes.toList()..sort()} 分钟前）。'
            '确认新的选择后会整体替换；取消则继续原样保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续编辑'),
            ),
          ],
        ),
      );
      if (shouldContinue != true || !mounted) return;
    }
    final result = await showReminderSelectionSheet(
      context: context,
      initialPresets: _reminderPresets,
      initialCustomAdvanceMinutes: _customReminderAdvanceMinutes,
      onRemainingTenPercentUnsupported: () => _showMessage('剩余 10% 提醒暂未开放'),
    );
    if (result == null || !mounted) return;
    setState(() {
      _reminderPresets = {...result.presets};
      _customReminderAdvanceMinutes = result.customAdvanceMinutes;
      _additionalCustomAdvanceMinutes = {};
      _remindersChanged = !_setEquals(
        _effectiveReminderAdvanceMinutes,
        _initialReminderAdvanceMinutes,
      );
    });
  }

  Future<void> _pickCategory() async {
    final result = await Navigator.of(context).push<CategoryPickerResult>(
      MaterialPageRoute<CategoryPickerResult>(
        builder: (_) => CategoryPickerPage(
          repository: widget.categoryRepository,
          selectedCategoryId: _selectedCategoryId,
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final selected = result.category;
    setState(() {
      _selectedCategoryId = selected?.id;
      _selectedCategoryName = selected?.name ?? '未分类';
      _categoryChanged = selected?.id != widget.detail.event.categoryId;
    });
  }

  void _handleAllDayChanged(bool value) {
    if (value && _effectiveReminderAdvanceMinutes.isNotEmpty) {
      _showMessage('请先清空提醒；全天重复日程暂不支持提醒');
      return;
    }
    setState(() {
      _isAllDay = value;
      _timeChanged = true;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showUnavailable(String message) {
    if (message == '时区选择功能后续实现') {
      _showMessage('重复系列固定使用原始时区 ${widget.detail.event.timezone}');
      return;
    }
    _showMessage(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NewScheduleColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            _EditSeriesTopBar(
              canSubmit: _canSubmit,
              isSubmitting: _isSubmitting,
              onCancel: () => Navigator.of(context).pop(false),
              onSubmit: _handleSubmit,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_initializationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_initializationError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _initialize, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NewScheduleSpacing.pageHorizontal,
        8,
        NewScheduleSpacing.pageHorizontal,
        NewScheduleSpacing.bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WholeSeriesNotice(),
          const SizedBox(height: NewScheduleSpacing.sectionGap),
          ManualScheduleForm(
            key: const ValueKey('edit-recurring-event-form'),
            titleController: _titleController,
            noteController: _noteController,
            locationController: _locationController,
            startAt: _startLocal,
            endAt: _endLocal,
            isAllDay: _isAllDay,
            isRingingReminderEnabled: false,
            isMoreSettingsExpanded: _isMoreSettingsExpanded,
            categoryLabel: _selectedCategoryName,
            recurrenceLabel: _recurrencePreset.label,
            reminderSummary: _reminderSummary,
            timezoneLabel: widget.detail.event.timezone,
            onAllDayChanged: _handleAllDayChanged,
            onRingingReminderChanged: (value) {
              if (value) _showMessage('重复日程本期仅支持弹窗提醒');
            },
            onMoreSettingsToggle: () {
              setState(() {
                _isMoreSettingsExpanded = !_isMoreSettingsExpanded;
              });
            },
            onStartTap: () => _pickStartDateTime(PickerInitialStep.calendar),
            onStartTimeTap: () => _pickStartDateTime(PickerInitialStep.time),
            onStartDateTap: () =>
                _pickStartDateTime(PickerInitialStep.calendar),
            onEndTap: () => _pickEndDateTime(PickerInitialStep.calendar),
            onEndTimeTap: () => _pickEndDateTime(PickerInitialStep.time),
            onEndDateTap: () => _pickEndDateTime(PickerInitialStep.calendar),
            onCategoryTap: _pickCategory,
            onRecurrenceTap: _pickRecurrence,
            onReminderTap: _pickReminders,
            onLocationMapTap: () => _showMessage('地图选择功能暂未开放'),
            onTodoTap: _showUnavailable,
          ),
        ],
      ),
    );
  }

  static ReminderPreset? _presetForAdvanceMinutes(int value) {
    return switch (value) {
      0 => ReminderPreset.atStart,
      15 => ReminderPreset.minutes15,
      30 => ReminderPreset.minutes30,
      60 => ReminderPreset.hour1,
      120 => ReminderPreset.hours2,
      1440 => ReminderPreset.day1,
      2880 => ReminderPreset.days2,
      10080 => ReminderPreset.week1,
      _ => null,
    };
  }

  static bool _setEquals(Set<int> first, Set<int> second) {
    return first.length == second.length && first.containsAll(second);
  }
}

class _EditSeriesTopBar extends StatelessWidget {
  const _EditSeriesTopBar({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NewScheduleSizes.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NewScheduleSpacing.topBarHorizontal,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('edit-series-cancel'),
                onPressed: onCancel,
                child: const Text('取消'),
              ),
            ),
            const Text('修改整个系列', style: NewScheduleTextStyles.pageTitle),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('edit-series-save'),
                onPressed: canSubmit ? onSubmit : null,
                child: Text(isSubmitting ? '保存中' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WholeSeriesNotice extends StatelessWidget {
  const _WholeSeriesNotice();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '修改整个重复系列',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: NewScheduleColors.accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
        ),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.repeat_rounded, color: NewScheduleColors.accent),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '本页修改会应用到整个重复系列；不支持仅修改本次或本次及以后。',
                  style: NewScheduleTextStyles.rowValue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

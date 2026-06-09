import 'package:flutter/material.dart';

import '../../application/event/create_event_use_case.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../shared/native_result_dialog.dart';
import 'components/create_mode_segmented_control.dart';
import 'components/manual_schedule_form.dart';
import 'components/new_schedule_top_bar.dart';
import 'date_time_picker/schedule_date_time_picker.dart';
import 'new_schedule_design_tokens.dart';
import 'schedule_submit_controller.dart';

enum CreateScheduleMode { manual, aiRecognition }

class NewSchedulePage extends StatefulWidget {
  const NewSchedulePage({required this.createUseCase, super.key});

  final CreateEventUseCase createUseCase;

  @override
  State<NewSchedulePage> createState() => _NewSchedulePageState();
}

class _NewSchedulePageState extends State<NewSchedulePage> {
  late final ScheduleSubmitController _submitController;
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  CreateScheduleMode _mode = CreateScheduleMode.manual;
  bool _isAllDay = false;
  bool _isRingingReminderEnabled = false;
  bool _isMoreSettingsExpanded = true;
  bool _isSubmitting = false;

  late DateTime _startAt;
  late DateTime _endAt;
  static const _timezoneLabel = 'GMT+08:00 北京';
  static const _timezoneId = 'Asia/Shanghai';

  @override
  void initState() {
    super.initState();
    _submitController = ScheduleSubmitController(widget.createUseCase);
    _startAt = _nextDefaultStartAt();
    _endAt = _startAt.add(const Duration(hours: 1));
    _titleController.addListener(_handleTitleChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleTitleChanged() {
    setState(() {});
  }

  static DateTime _nextDefaultStartAt() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(const Duration(hours: 1));
  }

  bool get _canSubmit =>
      _titleController.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    if (_endAt.isBefore(_startAt)) {
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间不能早于开始时间')));
      return;
    }

    final note = _noteController.text.trim();
    final request = CreateEventRequestDto(
      title: title,
      content: note.isEmpty ? null : note,
      startAt: _startAt,
      endAt: _endAt,
      isAllDay: _isAllDay,
      categoryId: '1',
      importance: 'unimportant_noturgent',
      timezone: _timezoneId,
      source: 'manual',
      reminders: const [],
    );

    final invocation = await _submitController.submit(request);
    if (!mounted) {
      return;
    }

    await showNativeResultDialog(
      context: context,
      title: 'event.create NativeResult',
      rawResponse: invocation.rawResponse,
    );
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
      _startAt = result.localDateTime;
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
      _endAt = result.localDateTime;
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
                        startAt: _startAt,
                        endAt: _endAt,
                        isAllDay: _isAllDay,
                        isRingingReminderEnabled: _isRingingReminderEnabled,
                        isMoreSettingsExpanded: _isMoreSettingsExpanded,
                        onAllDayChanged: (value) {
                          setState(() {
                            _isAllDay = value;
                          });
                        },
                        onRingingReminderChanged: (value) {
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

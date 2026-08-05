import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import 'calendar_date_panel.dart';
import 'picker_bottom_actions.dart';
import 'picker_date_math.dart';
import 'picker_design_tokens.dart';
import 'picker_header.dart';
import 'picker_selected_value_row.dart';
import 'schedule_date_time_picker.dart';
import 'time_wheel_panel.dart';
import 'year_month_day_wheel_panel.dart';

class ScheduleDateTimePickerSheet extends StatefulWidget {
  const ScheduleDateTimePickerSheet({
    required this.initialDateTime,
    required this.timezone,
    required this.target,
    required this.initialStep,
    super.key,
  });

  final DateTime initialDateTime;
  final String timezone;
  final PickerTarget target;
  final DateTimePickerStep initialStep;

  @override
  State<ScheduleDateTimePickerSheet> createState() =>
      _ScheduleDateTimePickerSheetState();
}

class _ScheduleDateTimePickerSheetState
    extends State<ScheduleDateTimePickerSheet> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late DateTime _visibleMonth;
  late CalendarSystem _calendarSystem;
  late DateTimePickerStep _step;
  DateTimePickerStep? _previousStep;
  var _monthDirection = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateTime;
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
    _selectedTime = TimeOfDay(hour: initial.hour, minute: initial.minute);
    _visibleMonth = DateTime(initial.year, initial.month);
    _calendarSystem = CalendarSystem.gregorian;
    _step = widget.initialStep;
  }

  String get _targetLabel => widget.target == PickerTarget.start ? '开始' : '结束';

  void _setStep(DateTimePickerStep step) {
    if (_step == step) {
      return;
    }
    setState(() {
      _previousStep = _step;
      _step = step;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _monthDirection = delta.sign;
      _visibleMonth = PickerDateMath.shiftMonth(_visibleMonth, delta);
    });
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _visibleMonth = DateTime(date.year, date.month);
    });
    await Future<void>.delayed(AppMotion.pickerAutoStepPause);
    if (!mounted || _step != DateTimePickerStep.calendar) {
      return;
    }
    _setStep(DateTimePickerStep.time);
  }

  void _selectYearMonthDay(DateTime date) {
    setState(() {
      _selectedDate = DateTime(date.year, date.month, date.day);
      _visibleMonth = DateTime(date.year, date.month);
      _previousStep = _step;
      _step = DateTimePickerStep.calendar;
    });
  }

  void _toggleCalendarSystem() {
    setState(() {
      _calendarSystem = _calendarSystem == CalendarSystem.gregorian
          ? CalendarSystem.lunar
          : CalendarSystem.gregorian;
    });
  }

  void _confirm() {
    final localDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    Navigator.of(context).pop(
      ScheduleDateTimeSelection(
        localDateTime: localDateTime,
        year: _selectedDate.year,
        month: _selectedDate.month,
        day: _selectedDate.day,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        timezone: widget.timezone,
        calendarSystem: _calendarSystem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final disableAnimations = media.disableAnimations;
    final screenHeight = media.size.height;
    final heightFactor = switch (_step) {
      DateTimePickerStep.calendar => 0.78,
      DateTimePickerStep.time => 0.55,
      DateTimePickerStep.yearMonthDay => 0.55,
    };
    final minHeight = screenHeight < 700 ? screenHeight * 0.66 : 430.0;
    final targetHeight = (screenHeight * heightFactor).clamp(
      minHeight,
      screenHeight * 0.78,
    );

    return AnimatedContainer(
      height: targetHeight,
      duration: disableAnimations ? Duration.zero : AppMotion.pickerPanel,
      curve: AppMotion.standard,
      decoration: const BoxDecoration(
        color: PickerColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PickerSizes.sheetRadius),
          bottom: Radius.circular(PickerSizes.sheetRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PickerSpacing.sheetHorizontal,
                26,
                PickerSpacing.sheetHorizontal,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PickerHeader(target: widget.target),
                  const SizedBox(height: 28),
                  PickerSelectedValueRow(
                    targetLabel: _targetLabel,
                    selectedDate: _selectedDate,
                    selectedTime: _selectedTime,
                    activeStep: _step,
                    onDateTap: () => _setStep(DateTimePickerStep.calendar),
                    onTimeTap: () => _setStep(DateTimePickerStep.time),
                  ),
                  const SizedBox(height: 14),
                  _buildPanel(disableAnimations),
                ],
              ),
            ),
          ),
          PickerBottomActions(
            onCancel: () => Navigator.of(context).pop(null),
            onConfirm: _confirm,
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(bool disableAnimations) {
    return AnimatedSwitcher(
      duration: disableAnimations ? Duration.zero : AppMotion.pickerPanel,
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      transitionBuilder: (child, animation) {
        final offset = _panelOffset(child.key);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: offset,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: switch (_step) {
        DateTimePickerStep.calendar => CalendarDatePanel(
          key: const ValueKey('calendar-panel'),
          selectedDate: _selectedDate,
          visibleMonth: _visibleMonth,
          today: DateTime.now(),
          calendarSystem: _calendarSystem,
          monthDirection: _monthDirection,
          target: widget.target,
          onPreviousMonth: () => _changeMonth(-1),
          onNextMonth: () => _changeMonth(1),
          onMonthTitleTap: () => _setStep(DateTimePickerStep.yearMonthDay),
          onDateSelected: _selectDate,
          onCalendarSystemToggle: _toggleCalendarSystem,
        ),
        DateTimePickerStep.time => TimeWheelPanel(
          key: const ValueKey('time-panel'),
          selectedTime: _selectedTime,
          onTimeChanged: (time) {
            setState(() {
              _selectedTime = time;
            });
          },
        ),
        DateTimePickerStep.yearMonthDay => YearMonthDayWheelPanel(
          key: const ValueKey('year-month-day-panel'),
          selectedDate: _selectedDate,
          onCommit: _selectYearMonthDay,
        ),
      },
    );
  }

  Offset _panelOffset(Key? key) {
    if (key == const ValueKey('year-month-day-panel')) {
      return const Offset(0, 0.06);
    }
    if (key == const ValueKey('time-panel')) {
      return const Offset(0.08, 0);
    }
    if (_previousStep == DateTimePickerStep.time) {
      return const Offset(-0.08, 0);
    }
    if (_previousStep == DateTimePickerStep.yearMonthDay) {
      return const Offset(0, -0.04);
    }
    return const Offset(-0.04, 0);
  }
}

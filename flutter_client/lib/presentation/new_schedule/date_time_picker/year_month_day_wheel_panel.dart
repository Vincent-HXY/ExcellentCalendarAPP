import 'package:flutter/material.dart';

import 'picker_date_math.dart';
import 'picker_design_tokens.dart';
import 'picker_wheel_column.dart';

class YearMonthDayWheelPanel extends StatefulWidget {
  const YearMonthDayWheelPanel({
    required this.selectedDate,
    required this.onCommit,
    super.key,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onCommit;

  @override
  State<YearMonthDayWheelPanel> createState() => _YearMonthDayWheelPanelState();
}

class _YearMonthDayWheelPanelState extends State<YearMonthDayWheelPanel> {
  late final int _minYear;
  late final int _maxYear;
  late int _year;
  late int _month;
  late int _day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _minYear = now.year - PickerDateMath.yearRangePadding;
    _maxYear = now.year + PickerDateMath.yearRangePadding;
    _year = widget.selectedDate.year.clamp(_minYear, _maxYear);
    _month = widget.selectedDate.month;
    _day = widget.selectedDate.day;
    _clampDay();
  }

  int get _yearCount => _maxYear - _minYear + 1;

  void _clampDay() {
    _day = PickerDateMath.clampedDay(year: _year, month: _month, day: _day);
  }

  void _commit() {
    widget.onCommit(DateTime(_year, _month, _day));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _commit,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$_year年$_month月',
                  style: PickerTextStyles.calendarMonth.copyWith(
                    color: PickerColors.primary,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_drop_up_rounded,
                  color: PickerColors.primary,
                  size: 24,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: PickerWheelColumn(
                        itemCount: _yearCount,
                        selectedIndex: _year - _minYear,
                        labelBuilder: (index) => '${_minYear + index}年',
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _year = _minYear + index;
                            _clampDay();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: PickerWheelColumn(
                        itemCount: 12,
                        selectedIndex: _month - 1,
                        labelBuilder: (index) => '${index + 1}月',
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _month = index + 1;
                            _clampDay();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: PickerWheelColumn(
                        itemCount: DateUtils.getDaysInMonth(_year, _month),
                        selectedIndex: _day - 1,
                        labelBuilder: (index) => '${index + 1}日',
                        onSelectedItemChanged: (index) {
                          setState(() {
                            _day = index + 1;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

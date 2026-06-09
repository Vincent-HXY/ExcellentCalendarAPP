import 'package:flutter/material.dart';

import 'picker_wheel_column.dart';

class TimeWheelPanel extends StatelessWidget {
  const TimeWheelPanel({
    required this.selectedTime,
    required this.onTimeChanged,
    super.key,
  });

  final TimeOfDay selectedTime;
  final ValueChanged<TimeOfDay> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PickerWheelColumn(
            width: 112,
            itemCount: 24,
            selectedIndex: selectedTime.hour,
            looping: true,
            labelBuilder: (index) => index.toString().padLeft(2, '0'),
            onSelectedItemChanged: (hour) {
              onTimeChanged(TimeOfDay(hour: hour, minute: selectedTime.minute));
            },
          ),
          PickerWheelColumn(
            width: 112,
            itemCount: 60,
            selectedIndex: selectedTime.minute,
            looping: true,
            labelBuilder: (index) => index.toString().padLeft(2, '0'),
            onSelectedItemChanged: (minute) {
              onTimeChanged(TimeOfDay(hour: selectedTime.hour, minute: minute));
            },
          ),
        ],
      ),
    );
  }
}

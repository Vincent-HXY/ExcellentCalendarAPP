import 'package:flutter/material.dart';

import 'picker_design_tokens.dart';
import 'schedule_date_time_picker.dart';

class PickerHeader extends StatelessWidget {
  const PickerHeader({required this.target, super.key});

  final PickerTarget target;

  @override
  Widget build(BuildContext context) {
    final title = target == PickerTarget.start ? '选择开始时间' : '选择结束时间';

    return Center(child: Text(title, style: PickerTextStyles.title));
  }
}

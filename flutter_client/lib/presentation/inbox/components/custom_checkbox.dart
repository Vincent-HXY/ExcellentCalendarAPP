// 文件作用：Inbox 任务行的圆形完成状态控件。
// 设计边界：当前是展示控件，没有手势和状态写回逻辑。
import 'package:flutter/material.dart';

import '../inbox_design_tokens.dart';

class CustomCheckbox extends StatelessWidget {
  const CustomCheckbox({
    required this.isChecked,
    required this.isImportant,
    super.key,
  });

  // 数据块作用：当前任务是否已完成，决定是否填充背景并显示对勾。
  final bool isChecked;
  // 数据块作用：当前任务是否重要，决定未完成状态下的边框强调色。
  final bool isImportant;

  @override
  Widget build(BuildContext context) {
    // 函数作用：根据完成态和重要性绘制圆形任务状态标记。
    // 关键判断：重要任务未完成时使用红色边框，完成后统一变灰。
    final borderColor = isImportant
        ? InboxColors.checkboxImportant
        : InboxColors.checkbox;
    final fillColor = isChecked ? InboxColors.checkbox : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: InboxSizes.checkbox,
      height: InboxSizes.checkbox,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(
          color: isChecked ? InboxColors.checkbox : borderColor,
          width: InboxSizes.checkboxBorder,
        ),
      ),
      child: isChecked
          ? const Icon(
              Icons.check_rounded,
              size: InboxSizes.checkIcon,
              color: Colors.white,
            )
          : null,
    );
  }
}

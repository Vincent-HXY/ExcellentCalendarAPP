// 文件作用：新建日程表单的白色圆角分区容器。
// 设计边界：只提供视觉包裹，不关心内部字段含义。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';

class FormSectionCard extends StatelessWidget {
  const FormSectionCard({required this.child, super.key});

  // 数据块作用：卡片内部要包裹的具体表单控件。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制统一白色圆角容器，让不同表单区块保持一致外观。
    return Container(
      decoration: BoxDecoration(
        color: NewScheduleColors.surface,
        borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

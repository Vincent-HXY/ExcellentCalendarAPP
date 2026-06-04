// 文件作用：新建日程页面顶部栏，展示取消、标题、完成/保存中状态。
// 设计边界：只根据 canSubmit/isSubmitting 表达 UI 状态，不做提交校验本身。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';

class NewScheduleTopBar extends StatelessWidget {
  const NewScheduleTopBar({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
    super.key,
  });

  // 数据块作用：完成按钮是否可点击。
  final bool canSubmit;
  // 数据块作用：当前是否处于提交中，决定按钮文案和禁用状态。
  final bool isSubmitting;
  // 数据块作用：取消按钮点击回调。
  final VoidCallback onCancel;
  // 数据块作用：完成按钮点击回调。
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    // 函数作用：构建新建页顶部导航栏，并根据提交状态切换完成按钮。
    // 关键状态：canSubmit 控制完成按钮是否可点，isSubmitting 控制按钮文案。
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
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: NewScheduleColors.accent,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('取消', style: NewScheduleTextStyles.navAction),
              ),
            ),
            const Text('新建日程', style: NewScheduleTextStyles.pageTitle),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: canSubmit ? onSubmit : null,
                style: TextButton.styleFrom(
                  foregroundColor: NewScheduleColors.accent,
                  disabledForegroundColor: NewScheduleColors.muted,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(52, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isSubmitting ? '保存中' : '完成',
                  style: NewScheduleTextStyles.navAction,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

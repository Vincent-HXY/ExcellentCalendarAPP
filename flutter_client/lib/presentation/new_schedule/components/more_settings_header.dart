// 文件作用：更多设置区域的折叠/展开标题行。
// 设计边界：只展示折叠态并回调点击事件，状态由页面或状态层维护。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';

class MoreSettingsHeader extends StatelessWidget {
  const MoreSettingsHeader({
    required this.isExpanded,
    required this.onTap,
    super.key,
  });

  // 数据块作用：是否展开更多设置，决定箭头方向。
  final bool isExpanded;
  // 数据块作用：点击标题行时触发的折叠/展开回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制更多设置标题行和折叠方向箭头。
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            const Text('更多设置', style: NewScheduleTextStyles.sectionTitle),
            const Spacer(),
            AnimatedRotation(
              turns: isExpanded ? -0.25 : 0.25,
              duration: const Duration(milliseconds: 160),
              child: const Icon(
                Icons.chevron_right_rounded,
                color: NewScheduleColors.muted,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

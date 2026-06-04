// 文件作用：新建日程的创建方式切换控件，当前支持手动填写和一键识别两个模式。
// 设计边界：只切换页面展示；一键识别的候选日程生成应由 AI Pipeline/Application 处理。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import '../new_schedule_page.dart';

class CreateModeSegmentedControl extends StatelessWidget {
  const CreateModeSegmentedControl({
    required this.selectedMode,
    required this.onChanged,
    super.key,
  });

  // 数据块作用：当前选中的创建模式，控制哪个按钮处于选中态。
  final CreateScheduleMode selectedMode;
  // 数据块作用：切换创建模式时通知父页面更新状态。
  final ValueChanged<CreateScheduleMode> onChanged;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制手动填写/一键识别分段切换控件。
    return Container(
      height: NewScheduleSizes.segmentedHeight,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NewScheduleColors.controlBackground,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: '手动填写',
            isSelected: selectedMode == CreateScheduleMode.manual,
            onTap: () => onChanged(CreateScheduleMode.manual),
          ),
          _SegmentButton(
            label: '一键识别',
            isSelected: selectedMode == CreateScheduleMode.recognition,
            onTap: () => onChanged(CreateScheduleMode.recognition),
          ),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  // 数据块作用：按钮显示文案。
  final String label;
  // 数据块作用：是否为当前选中模式，决定背景色。
  final bool isSelected;
  // 数据块作用：点击按钮时触发模式切换。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制分段控件里的单个可点击按钮。
    // 关键视觉：选中态用白色胶囊块浮在半透明轨道上。
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? NewScheduleColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label, style: NewScheduleTextStyles.segment),
        ),
      ),
    );
  }
}

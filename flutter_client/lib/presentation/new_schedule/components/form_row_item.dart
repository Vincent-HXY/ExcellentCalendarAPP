// 文件作用：新建日程表单里的通用行组件，支持 label/value/trailing/chevron/divider。
// 设计边界：只处理展示和点击回调，不保存任何表单字段。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';

class FormRowItem extends StatelessWidget {
  const FormRowItem({
    required this.label,
    this.value,
    this.trailing,
    this.showChevron = true,
    this.showDivider = false,
    this.onTap,
    super.key,
  });

  // 数据块作用：左侧字段名称，例如全天、提醒、地点、日历分类。
  final String label;
  // 数据块作用：右侧文本值，例如仅一次、15 分钟前、默认日程。
  final String? value;
  // 数据块作用：右侧自定义控件，例如 Switch 或地点图标。
  final Widget? trailing;
  // 数据块作用：是否显示右侧箭头，表示该行可进入下一级选择。
  final bool showChevron;
  // 数据块作用：是否显示底部分割线，用于同一卡片内多行分隔。
  final bool showDivider;
  // 数据块作用：点击整行时触发的父级回调。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：构建一行通用表单项，并根据配置显示 value、trailing、箭头和分割线。
    // 关键布局：value 和 trailing 都是可选内容，长文本会右侧省略以保护表单行高度。
    final row = SizedBox(
      height: NewScheduleSizes.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NewScheduleSpacing.rowHorizontal,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NewScheduleTextStyles.rowLabel,
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: NewScheduleTextStyles.rowValue,
                ),
              ),
            ?trailing,
            if (showChevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: NewScheduleColors.muted,
                size: 24,
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(onTap: onTap, child: row),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: NewScheduleSpacing.rowHorizontal,
            ),
            child: Divider(
              height: 1,
              thickness: 1,
              color: NewScheduleColors.divider,
            ),
          ),
      ],
    );
  }
}

// 文件作用：新建日程表单的标题输入卡片，并展示分类选择入口。
// 设计边界：只收集标题文字并转发分类点击，不保存 Category 业务状态。
import 'package:flutter/material.dart';

import '../new_schedule_design_tokens.dart';
import 'form_row_item.dart';
import 'form_section_card.dart';

class TextInputCard extends StatelessWidget {
  const TextInputCard({
    required this.titleController,
    required this.categoryLabel,
    required this.onCategoryTap,
    super.key,
  });

  // 数据块作用：标题输入控制器，由页面统一读取并提交。
  final TextEditingController titleController;
  // 数据块作用：当前分类的可见名称，不作为 Event 持久化关联。
  final String categoryLabel;
  // 数据块作用：点击分类行时触发的父级回调。
  final VoidCallback onCategoryTap;

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制标题输入框和分类选择入口。
    // 关键字体：标题输入使用大字号，maxLines=2 防止长标题无限撑高卡片。
    return FormSectionCard(
      child: Column(
        children: [
          SizedBox(
            height: NewScheduleSizes.titleInputHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: TextField(
                controller: titleController,
                maxLines: 2,
                style: NewScheduleTextStyles.titleInput,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '请输入日程名称',
                  hintStyle: TextStyle(
                    color: NewScheduleColors.muted,
                    fontSize: 28,
                    fontWeight: FontWeight.w400,
                  ),
                  isCollapsed: true,
                ),
              ),
            ),
          ),
          FormRowItem(label: '分类', value: categoryLabel, onTap: onCategoryTap),
        ],
      ),
    );
  }
}

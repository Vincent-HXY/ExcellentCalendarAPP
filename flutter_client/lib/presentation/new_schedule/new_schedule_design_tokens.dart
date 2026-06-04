// 文件作用：集中管理新建日程页面的颜色、间距、尺寸和文字样式。
// 设计边界：复用 Inbox 的基础色，保证两个页面视觉一致，不放表单业务规则。
import 'package:flutter/material.dart';

import '../inbox/inbox_design_tokens.dart';

class NewScheduleColors {
  const NewScheduleColors._();

  // 数据块作用：新建页颜色集合，大部分继承 Inbox 颜色以保持页面风格统一。
  // 关键视觉：页面背景、表单卡片和主强调色沿用 Inbox 首页 token。
  static const pageBackground = InboxColors.pageBackground;
  static const surface = InboxColors.surface;
  static const accent = InboxColors.accent;
  static const title = InboxColors.titleSoft;
  static const body = InboxColors.body;
  static const muted = InboxColors.mutedText;
  static const divider = Color(0xFFF0F2F3);
  static const controlBackground = Color(0x22000000);
  static const switchOff = Color(0xFFD5D9DC);
}

class NewScheduleSpacing {
  const NewScheduleSpacing._();

  // 数据块作用：新建页间距集合，控制页面边距、卡片间距和表单行内边距。
  static const pageHorizontal = 22.0;
  static const topBarHorizontal = 18.0;
  static const sectionGap = 12.0;
  static const cardHorizontal = 22.0;
  static const rowHorizontal = 24.0;
  static const bottomPadding = 32.0;
}

class NewScheduleSizes {
  const NewScheduleSizes._();

  // 数据块作用：新建页固定尺寸集合，控制顶部栏、分段控件、行高和输入区域高度。
  // 关键布局：输入框、时间卡和行高决定表单密度，移动端小屏需重点回归。
  static const topBarHeight = 58.0;
  static const cardRadius = 26.0;
  static const segmentedHeight = 44.0;
  static const rowHeight = 54.0;
  static const titleInputHeight = 118.0;
  static const noteHeight = 100.0;
}

class NewScheduleTextStyles {
  const NewScheduleTextStyles._();

  // 数据块作用：新建页文字样式集合，统一导航、标题、表单行和时间文本。
  // 关键字体：标题输入使用较大字号，调整时要检查 hint 和双行输入是否溢出。
  static const navAction = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const pageTitle = TextStyle(
    color: NewScheduleColors.title,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const segment = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const titleInput = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const rowLabel = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const rowValue = TextStyle(
    color: NewScheduleColors.muted,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const timeLabel = TextStyle(
    color: NewScheduleColors.muted,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const timeValue = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1,
  );

  static const dateValue = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1,
  );

  static const sectionTitle = TextStyle(
    color: NewScheduleColors.body,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1,
  );
}

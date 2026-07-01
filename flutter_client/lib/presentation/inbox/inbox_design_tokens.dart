// 文件作用：集中管理 Inbox 首页的颜色、间距、尺寸和字体样式。
// 设计边界：这里只放视觉 token，不放业务状态或任务分组逻辑。
import 'package:flutter/material.dart';

import '../app_design_tokens.dart';

class InboxColors {
  const InboxColors._();

  // 数据块作用：Inbox 页面使用的固定颜色集合，避免颜色散落在各组件中。
  // 关键视觉：页面背景和主强调色决定当前首页的整体品牌观感。
  static const pageBackground = Color(0xFFE6F8FA);
  static const surface = Colors.white;
  static const title = Color(0xFF111518);
  static const titleSoft = Color(0xFF111827);
  static const body = Color(0xFF1C2326);
  static const mutedText = Color(0xFF9AA3A7);
  static const divider = Color(0xFFF1F3F4);
  static const dueDate = Color(0xFF8F2D2F);
  static const checkbox = Color(0xFFC5CCD0);
  static const checkboxImportant = Color(0xFFE15E64);
  static const accent = Color(0xFF38B9C5);
  static const success = Color(0xFF5E9C78);
}

class InboxSpacing {
  const InboxSpacing._();

  // 数据块作用：Inbox 页面布局间距，控制页面边距、卡片间距和列表行内部间距。
  static const pageHorizontal = 22.0;
  static const cardTop = 14.0;
  static const contentBottom = 104.0;
  static const cardVerticalPadding = 8.0;
  static const groupSpacing = 12.0;
  static const groupHeaderHorizontal = 22.0;
  static const groupHeaderGap = 10.0;
  static const rowHorizontal = 22.0;
  static const checkboxGap = 2.0;
  static const dateGap = 10.0;
}

class InboxSizes {
  const InboxSizes._();

  // 数据块作用：Inbox 页面固定尺寸，控制顶部栏、分组标题、任务行和按钮大小。
  // 关键布局：rowHeight 影响列表一屏可见任务数量，widget_test 中有覆盖。
  static const topBarHeight = 62.0;
  static const topBarIconButton = 36.0;
  static const topBarIcon = 25.0;
  static const groupHeaderHeight = 48.0;
  static const rowHeight = 44.0;
  static const cardRadius = AppRadius.sectionCard;
  static const checkbox = 22.0;
  static const checkboxBorder = 2.0;
  static const checkIcon = 15.0;
  static const dateMaxWidth = 58.0;
}

class InboxTextStyles {
  const InboxTextStyles._();

  // 数据块作用：Inbox 页面字体样式集合，统一标题、任务名、日期和计数字体。
  // 关键字体：任务行和日期字体较小，调整时注意 390x844 小屏测试。
  static const headerTitle = TextStyle(
    color: InboxColors.titleSoft,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  static const taskTitle = TextStyle(
    color: InboxColors.body,
    fontSize: 15.5,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );

  static const dueDate = TextStyle(
    color: InboxColors.dueDate,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );

  static const groupTitle = TextStyle(
    color: InboxColors.titleSoft,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  static const groupCount = TextStyle(
    color: InboxColors.mutedText,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1,
  );
}

// 文件作用：Flutter 客户端入口，负责创建根 MaterialApp 并装配当前首页依赖。
// 设计边界：这里只做应用启动和依赖注入，真实业务流程仍应下沉到 Application/Gateway。
import 'package:flutter/material.dart';

import 'application/mock_inbox_task_adapter.dart';
import 'application/mock_schedule_create_use_case.dart';
import 'presentation/inbox/inbox_page.dart';

void main() {
  // 函数作用：启动 Flutter 应用，并把根组件交给 Flutter 渲染树。
  runApp(const ExcellentCalendarApp());
}

// 数据块作用：应用根组件，集中配置主题、首页和当前阶段的 mock 依赖。
class ExcellentCalendarApp extends StatelessWidget {
  const ExcellentCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 函数作用：构建全局 MaterialApp 外壳，决定应用标题、主题和默认首页。
    return MaterialApp(
      title: 'Excellent Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 关键视觉：全局主题种子色与 Inbox/NewSchedule 的 accent 保持一致。
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38B9C5)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: InboxPage(
        gateway: MockInboxTaskAdapter(),
        scheduleCreateUseCase: MockScheduleCreateUseCase(),
      ),
    );
  }
}

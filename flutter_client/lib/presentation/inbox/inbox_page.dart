// 文件作用：Inbox 首页容器，负责加载任务、展示顶部栏/列表/底部导航，并打开新建日程页。
// 设计边界：页面只编排 UI 状态和导航，不直接读取本地文件或调用 native 能力。
import 'package:flutter/material.dart';

import '../../gateway_interfaces/inbox_task_gateway.dart';
import '../../gateway_interfaces/schedule_create_use_case.dart';
import 'components/add_task_button.dart';
import 'components/bottom_nav_bar.dart';
import 'components/inbox_top_bar.dart';
import 'components/task_list_card.dart';
import 'inbox_design_tokens.dart';
import 'models/inbox_task_view_data.dart';
import '../new_schedule/new_schedule_page.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    required this.gateway,
    required this.scheduleCreateUseCase,
    super.key,
  });

  final InboxTaskGateway gateway;
  final ScheduleCreateUseCase scheduleCreateUseCase;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  // 数据块作用：缓存首页任务加载结果，当前页面生命周期内只加载一次。
  late final Future<List<InboxTaskViewData>> _tasksFuture;

  @override
  void initState() {
    // 函数作用：页面初始化时拉取首页任务数据，准备交给 FutureBuilder 展示。
    super.initState();
    // 关键数据：任务只在页面初始化时加载一次；后续需要创建后刷新时应改为显式状态管理。
    _tasksFuture = widget.gateway.loadInboxTasks();
  }

  Future<void> _openNewSchedulePage() {
    // 函数作用：打开新建日程页面，并配置从底部轻微上浮的页面切换动画。
    // 关键交互：自定义过渡只属于 Presentation；保存成功后的刷新策略应交给状态层处理。
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) {
          return NewSchedulePage(createUseCase: widget.scheduleCreateUseCase);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInOutCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 函数作用：构建 Inbox 首页整体布局，包括顶部栏、任务卡、悬浮新增按钮和底部导航。
    return Scaffold(
      backgroundColor: InboxColors.pageBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InboxTopBar(),
                Expanded(
                  child: FutureBuilder<List<InboxTaskViewData>>(
                    future: _tasksFuture,
                    builder: (context, snapshot) {
                      // 关键状态：当前未区分 loading/error/empty，真实网关接入后应补齐。
                      final tasks = snapshot.data ?? const [];

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          InboxSpacing.pageHorizontal,
                          InboxSpacing.cardTop,
                          InboxSpacing.pageHorizontal,
                          InboxSpacing.contentBottom,
                        ),
                        child: TaskListCard(tasks: tasks),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              right: 36,
              bottom: 96,
              child: AddTaskButton(onPressed: _openNewSchedulePage),
            ),
            const Positioned(
              left: 32,
              right: 32,
              bottom: 14,
              child: BottomNavBar(selectedIndex: 0),
            ),
          ],
        ),
      ),
    );
  }
}

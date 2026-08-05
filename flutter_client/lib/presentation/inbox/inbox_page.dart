import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/event/complete_event_use_case.dart';
import '../../application/event/create_event_use_case.dart';
import '../../application/event/read_events_use_case.dart';
import '../../application/timezone/timezone_application_service.dart';
import '../app_design_tokens.dart';
import '../event_detail/models/event_detail_ui_state.dart';
import '../event_detail/pages/event_detail_page.dart';
import '../new_schedule/new_schedule_page.dart';
import 'components/add_task_button.dart';
import 'components/bottom_nav_bar.dart';
import 'components/inbox_top_bar.dart';
import 'components/task_list_card.dart';
import 'inbox_controller.dart';
import 'inbox_design_tokens.dart';
import 'models/inbox_task_view_data.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    required this.readEventsUseCase,
    required this.createEventUseCase,
    required this.completeEventUseCase,
    required this.timezoneService,
    super.key,
  });

  final ReadEventsUseCase readEventsUseCase;
  final CreateEventUseCase createEventUseCase;
  final CompleteEventUseCase completeEventUseCase;
  final TimezoneApplicationService timezoneService;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  late final InboxController _controller;

  @override
  void initState() {
    super.initState();
    _controller = InboxController(
      readEventsUseCase: widget.readEventsUseCase,
      completeEventUseCase: widget.completeEventUseCase,
      timezoneService: widget.timezoneService,
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _completeTask(InboxTaskViewData task) async {
    final result = await _controller.completeTask(task);
    if (!mounted) {
      return false;
    }
    if (!result.succeeded) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.errorMessage ?? '完成日程失败')));
    }
    return result.succeeded;
  }

  Future<EventDetailCompletionResult> _completeTaskFromDetail(
    InboxTaskViewData task,
  ) async {
    final result = await _controller.completeTask(task);
    if (!result.succeeded) {
      return EventDetailCompletionResult.failure(
        result.errorMessage ??
            '\u5b8c\u6210\u65e5\u7a0b\u5931\u8d25\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5',
      );
    }
    return const EventDetailCompletionResult.success();
  }

  Future<void> _openEventDetail(InboxTaskViewData task) async {
    final detailState = task.detailState;
    if (detailState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u6682\u65e0\u6cd5\u52a0\u8f7d\u65e5\u7a0b\u8be6\u60c5',
          ),
        ),
      );
      return;
    }

    final didComplete = await Navigator.of(context).pushNamed<bool>(
      '/event/detail/${task.id}',
      arguments: EventDetailPageArguments(
        state: detailState,
        onEdit: _showEditUnavailable,
        onComplete: () => _completeTaskFromDetail(task),
        onEditField: (_) => _showEditUnavailable(),
        canComplete: !task.isCompleted && !task.hasRecurrence,
      ),
    );
    if (!mounted || didComplete != true) return;

    _controller.finalizeCompletion(task.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u65e5\u7a0b\u5df2\u5b8c\u6210')),
    );
  }

  void _showEditUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u7f16\u8f91\u529f\u80fd\u6682\u4e0d\u652f\u6301\uff0c\u540e\u7eed\u5f00\u53d1\u518d\u5b8c\u5584',
        ),
      ),
    );
  }

  Future<void> _openNewSchedulePage() async {
    final didCreate = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: AppMotion.routeEnter,
        reverseTransitionDuration: AppMotion.routeExit,
        pageBuilder: (context, animation, secondaryAnimation) {
          return NewSchedulePage(
            createUseCase: widget.createEventUseCase,
            timezoneService: widget.timezoneService,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: AppMotion.enter,
            reverseCurve: AppMotion.standard,
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

    if (didCreate == true && mounted) {
      await _controller.loadActive();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      InboxSpacing.pageHorizontal,
                      InboxSpacing.cardTop,
                      InboxSpacing.pageHorizontal,
                      InboxSpacing.contentBottom,
                    ),
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (context, child) => _buildContent(),
                    ),
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

  Widget _buildContent() {
    if (_controller.isLoadingActive && _controller.activeTasks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: InboxColors.accent),
      );
    }
    if (_controller.activeError != null && _controller.activeTasks.isEmpty) {
      return _InboxStatusCard(
        title: '读取日程失败',
        body: _controller.activeError!,
        actionLabel: '重试',
        onAction: _controller.loadActive,
      );
    }
    return TaskListCard(
      tasks: _controller.activeTasks,
      completedTasks: _controller.completedTasks,
      completedCountLabel: _controller.completedCountLabel,
      completingIds: _controller.completingIds,
      isLoadingCompleted: _controller.isLoadingCompleted,
      completedError: _controller.completedError,
      onTaskComplete: _completeTask,
      onTaskRemovalFinished: _controller.finalizeCompletion,
      onCompletedExpandedChanged: _controller.setCompletedExpanded,
      onTaskTap: _openEventDetail,
    );
  }
}

class _InboxStatusCard extends StatelessWidget {
  const _InboxStatusCard({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: InboxColors.surface,
        borderRadius: BorderRadius.circular(InboxSizes.cardRadius),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: InboxColors.titleSoft,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: InboxTextStyles.groupCount,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

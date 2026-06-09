import 'package:flutter/material.dart';

import '../../application/event/create_event_use_case.dart';
import '../../application/event/read_events_use_case.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../app_design_tokens.dart';
import '../new_schedule/new_schedule_page.dart';
import '../shared/native_result_dialog.dart';
import 'components/add_task_button.dart';
import 'components/bottom_nav_bar.dart';
import 'components/inbox_top_bar.dart';
import 'components/task_list_card.dart';
import 'inbox_design_tokens.dart';
import 'models/inbox_task_view_data.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({
    required this.readEventsUseCase,
    required this.createEventUseCase,
    super.key,
  });

  final ReadEventsUseCase readEventsUseCase;
  final CreateEventUseCase createEventUseCase;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  var _isLoading = false;
  String? _errorText;
  List<InboxTaskViewData> _tasks = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readEvents();
    });
  }

  Future<void> _readEvents() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final invocation = await widget.readEventsUseCase.execute();
    if (!mounted) {
      return;
    }

    await showNativeResultDialog(
      context: context,
      title: 'event.search NativeResult',
      rawResponse: invocation.rawResponse,
    );
    if (!mounted) {
      return;
    }

    final nativeResult = invocation.result;
    setState(() {
      _isLoading = false;
      if (nativeResult.ok) {
        _tasks = nativeResult.data!.items
            .map(_toInboxTask)
            .toList(growable: false);
        _errorText = null;
      } else {
        _tasks = const [];
        final error = nativeResult.error;
        _errorText = error == null
            ? '读取日程失败'
            : '${error.code}: ${error.message}\nrequest_id=${nativeResult.requestId ?? '-'} retryable=${error.retryable}';
      }
    });
  }

  InboxTaskViewData _toInboxTask(EventResponseDto event) {
    return InboxTaskViewData(
      id: event.id,
      title: event.title,
      dueDateLabel: _formatDueDate(event.startAt),
      importance: _mapImportance(event.importance),
      isCompleted: false,
    );
  }

  TaskImportance _mapImportance(String? importance) {
    return switch (importance) {
      'important_noturgent' => TaskImportance.importantNotUrgent,
      'unimportant_urgent' => TaskImportance.unimportantUrgent,
      'important_urgent' => TaskImportance.importantUrgent,
      _ => TaskImportance.unimportantNotUrgent,
    };
  }

  String _formatDueDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openNewSchedulePage() async {
    final didCreate = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: AppMotion.routeEnter,
        reverseTransitionDuration: AppMotion.routeExit,
        pageBuilder: (context, animation, secondaryAnimation) {
          return NewSchedulePage(createUseCase: widget.createEventUseCase);
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
      await _readEvents();
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
                    child: _buildContent(),
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
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: InboxColors.accent),
      );
    }
    if (_errorText != null) {
      return _InboxStatusCard(
        title: '读取日程失败',
        body: _errorText!,
        actionLabel: '重试',
        onAction: _readEvents,
      );
    }
    if (_tasks.isEmpty) {
      return const _InboxStatusCard(title: '暂无日程', body: '当前 native 数据源返回空列表');
    }
    return TaskListCard(tasks: _tasks);
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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../inbox_design_tokens.dart';
import '../models/inbox_task_view_data.dart';
import 'custom_checkbox.dart';

class TaskListItem extends StatefulWidget {
  const TaskListItem({
    required this.task,
    required this.showDivider,
    this.isCompleting = false,
    this.onComplete,
    this.onRemovalFinished,
    super.key,
  });

  final InboxTaskViewData task;
  final bool showDivider;
  final bool isCompleting;
  final Future<bool> Function()? onComplete;
  final VoidCallback? onRemovalFinished;

  @override
  State<TaskListItem> createState() => _TaskListItemState();
}

class _TaskListItemState extends State<TaskListItem>
    with TickerProviderStateMixin {
  late final AnimationController _strikeController;
  late final AnimationController _fadeController;
  late final AnimationController _collapseController;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<double> _sizeFactor;
  bool _isHandlingTap = false;

  @override
  void initState() {
    super.initState();
    _strikeController = AnimationController(
      vsync: this,
      duration: AppMotion.taskStrikeThrough,
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: AppMotion.taskFadeOut,
    );
    _collapseController = AnimationController(
      vsync: this,
      duration: AppMotion.taskCollapse,
    );
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _scale = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _sizeFactor = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _collapseController,
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _strikeController.dispose();
    _fadeController.dispose();
    _collapseController.dispose();
    super.dispose();
  }

  Future<void> _handleComplete() async {
    if (_isHandlingTap ||
        widget.isCompleting ||
        widget.task.isCompleted ||
        widget.task.hasRecurrence ||
        widget.onComplete == null) {
      return;
    }
    setState(() {
      _isHandlingTap = true;
    });

    final succeeded = await widget.onComplete!();
    if (!mounted) {
      return;
    }
    if (!succeeded) {
      setState(() {
        _isHandlingTap = false;
      });
      return;
    }

    if (MediaQuery.disableAnimationsOf(context)) {
      widget.onRemovalFinished?.call();
      return;
    }
    await _strikeController.forward();
    if (!mounted) {
      return;
    }
    await _fadeController.forward();
    if (!mounted) {
      return;
    }
    await _collapseController.forward();
    if (mounted) {
      widget.onRemovalFinished?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final titleStyle = InboxTextStyles.taskTitle.copyWith(
      color: task.isCompleted
          ? InboxColors.mutedText
          : InboxTextStyles.taskTitle.color,
      decoration: task.isCompleted ? TextDecoration.lineThrough : null,
      decorationColor: InboxColors.mutedText,
    );
    final canComplete = !task.isCompleted && !task.hasRecurrence;
    final isBusy = _isHandlingTap || widget.isCompleting;

    return SizeTransition(
      sizeFactor: _sizeFactor,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.centerLeft,
          child: Container(
            height: InboxSizes.rowHeight,
            decoration: BoxDecoration(
              border: widget.showDivider
                  ? const Border(
                      bottom: BorderSide(
                        color: InboxColors.divider,
                        width: 0.75,
                      ),
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: InboxSpacing.rowHorizontal,
              ),
              child: Row(
                children: [
                  CustomCheckbox(
                    isChecked: task.isCompleted,
                    isImportant: task.importance.isImportant,
                    isBusy: isBusy,
                    onTap: canComplete ? _handleComplete : null,
                  ),
                  const SizedBox(width: InboxSpacing.checkboxGap),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _strikeController,
                      builder: (context, child) {
                        return CustomPaint(
                          foregroundPainter: _StrikeRevealPainter(
                            text: task.title,
                            style: titleStyle,
                            textDirection: Directionality.of(context),
                            progress: _strikeController.value,
                          ),
                          child: child,
                        );
                      },
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                  if (task.dueDateLabel != null) ...[
                    const SizedBox(width: InboxSpacing.dateGap),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: InboxSizes.dateMaxWidth,
                      ),
                      child: Text(
                        task.dueDateLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: task.isCompleted
                            ? InboxTextStyles.dueDate.copyWith(
                                color: InboxColors.mutedText,
                              )
                            : InboxTextStyles.dueDate,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrikeRevealPainter extends CustomPainter {
  const _StrikeRevealPainter({
    required this.text,
    required this.style,
    required this.textDirection,
    required this.progress,
  });

  final String text;
  final TextStyle style;
  final TextDirection textDirection;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) {
      return;
    }
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textDirection: textDirection,
    )..layout(maxWidth: size.width);
    final lineWidth = math.min(textPainter.width, size.width) * progress;
    final paint = Paint()
      ..color = InboxColors.mutedText
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final y = size.height * 0.52;
    canvas.drawLine(Offset(0, y), Offset(lineWidth, y), paint);
  }

  @override
  bool shouldRepaint(covariant _StrikeRevealPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.text != text ||
        oldDelegate.style != style ||
        oldDelegate.textDirection != textDirection;
  }
}

// 文件作用：新建日程页面容器，管理表单 UI 状态并提交 EventDraft。
// 设计边界：当前页面直接组装 draft 是过渡实现，默认提醒/分类/时间规则后续应由 Application 编排。
import 'dart:math';

import 'package:flutter/material.dart';

import '../../gateway_interfaces/schedule_create_use_case.dart';
import 'components/create_mode_segmented_control.dart';
import 'components/manual_schedule_form.dart';
import 'components/new_schedule_top_bar.dart';
import 'new_schedule_design_tokens.dart';
import 'schedule_submit_controller.dart';

enum CreateScheduleMode { manual, recognition }

class NewSchedulePage extends StatefulWidget {
  const NewSchedulePage({required this.createUseCase, super.key});

  // 数据块作用：创建日程用例，由父页面注入，提交按钮最终会调用它。
  final ScheduleCreateUseCase createUseCase;

  @override
  State<NewSchedulePage> createState() => _NewSchedulePageState();
}

class _NewSchedulePageState extends State<NewSchedulePage> {
  // 数据块作用：提交控制器，隔离页面和 use case 的直接调用细节。
  late final ScheduleSubmitController _submitController;
  // 数据块作用：当前草稿 ID，页面初始化时生成，提交时写入 EventDraft。
  late final String _draftId;
  // 数据块作用：日程标题输入框状态，是完成按钮能否点击的主要依据。
  final _titleController = TextEditingController();
  // 数据块作用：备注输入框状态，提交时为空则不会写入 content。
  final _noteController = TextEditingController();

  // 数据块作用：当前创建模式，决定显示手动表单还是识别占位内容。
  CreateScheduleMode _mode = CreateScheduleMode.manual;
  // 数据块作用：全天开关状态，提交时写入 EventDraft.isAllDay。
  bool _isAllDay = false;
  // 数据块作用：响铃提醒开关状态，目前仅影响 UI，尚未生成 Reminder。
  bool _isRingingReminderEnabled = false;
  // 数据块作用：更多设置折叠状态，控制下方高级表单项是否显示。
  bool _isMoreSettingsExpanded = true;
  // 数据块作用：提交中状态，用于禁用完成按钮并显示“保存中”文案。
  bool _isSubmitting = false;

  // 关键数据：这些时间是开发期硬编码默认值；真实版本应来自时间选择器或用户设置。
  final DateTime _startAt = DateTime(2026, 6, 3, 8);
  final DateTime _endAt = DateTime(2026, 6, 3, 9);
  final DateTime _createdAt = DateTime(2026, 6, 3, 7);
  final DateTime _updatedAt = DateTime(2026, 6, 3, 7);

  @override
  void initState() {
    // 函数作用：初始化提交控制器、临时草稿 ID，并监听标题输入变化。
    super.initState();
    _submitController = ScheduleSubmitController(widget.createUseCase);
    // 关键数据：当前用随机数字做临时 ID；正式数据模型建议使用 UUID。
    _draftId = (Random().nextInt(900000) + 100000).toString();
    _titleController.addListener(_handleTitleChanged);
  }

  @override
  void dispose() {
    // 函数作用：释放文本输入控制器和监听器，避免页面销毁后的资源泄漏。
    _titleController.removeListener(_handleTitleChanged);
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _handleTitleChanged() {
    // 函数作用：标题变化时刷新页面，让完成按钮的可点击状态即时更新。
    setState(() {});
  }

  bool get _canSubmit =>
      // 函数作用：判断当前表单是否允许提交；标题为空或正在提交时不可提交。
      _titleController.text.trim().isNotEmpty && !_isSubmitting;

  Future<void> _handleSubmit() async {
    // 函数作用：收集当前表单状态，构建 EventDraft，并调用提交控制器。
    final title = _titleController.text.trim();
    if (title.isEmpty || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final draft = EventDraft(
      id: _draftId,
      title: title,
      content: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      startAt: _startAt,
      endAt: _endAt,
      isAllDay: _isAllDay,
      createdAt: _createdAt,
      updatedAt: _updatedAt,
      hasRecurrence: false,
      // 关键数据：分类、时区、来源当前为占位值；后续应来自分类选择、用户时区和 source 枚举。
      categoryId: '1',
      timezone: 'GMT+08:00 北京',
      source: '手动添加',
    );

    try {
      await _submitController.submit(draft);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(
        context,
        // 关键状态：这里仅展示提交失败；真实用例接入后应收敛错误类型和用户文案。
      ).showSnackBar(SnackBar(content: Text('创建失败：$error')));
    }
  }

  void _showTodo(String message) {
    // 函数作用：展示“功能后续实现”的临时提示，用于占位未完成表单入口。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // 函数作用：构建新建日程页面，包括顶部栏、模式切换和对应表单内容。
    return Scaffold(
      backgroundColor: NewScheduleColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            NewScheduleTopBar(
              canSubmit: _canSubmit,
              isSubmitting: _isSubmitting,
              onCancel: () => Navigator.of(context).pop(false),
              onSubmit: _handleSubmit,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NewScheduleSpacing.pageHorizontal,
                  8,
                  NewScheduleSpacing.pageHorizontal,
                  NewScheduleSpacing.bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreateModeSegmentedControl(
                      selectedMode: _mode,
                      onChanged: (mode) {
                        setState(() {
                          _mode = mode;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_mode == CreateScheduleMode.manual)
                      ManualScheduleForm(
                        titleController: _titleController,
                        noteController: _noteController,
                        isAllDay: _isAllDay,
                        isRingingReminderEnabled: _isRingingReminderEnabled,
                        isMoreSettingsExpanded: _isMoreSettingsExpanded,
                        onAllDayChanged: (value) {
                          setState(() {
                            _isAllDay = value;
                          });
                        },
                        onRingingReminderChanged: (value) {
                          setState(() {
                            _isRingingReminderEnabled = value;
                          });
                        },
                        onMoreSettingsToggle: () {
                          setState(() {
                            _isMoreSettingsExpanded = !_isMoreSettingsExpanded;
                          });
                        },
                        onTodoTap: _showTodo,
                      )
                    else
                      const _RecognitionPlaceholder(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecognitionPlaceholder extends StatelessWidget {
  const _RecognitionPlaceholder();

  @override
  Widget build(BuildContext context) {
    // 函数作用：绘制一键识别模式的占位内容，保留未来 AI 入口位置。
    // 关键占位：一键识别属于 AI Pipeline 候选日程流程，当前仅保留入口。
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      decoration: BoxDecoration(
        color: NewScheduleColors.surface,
        borderRadius: BorderRadius.circular(NewScheduleSizes.cardRadius),
      ),
      child: const Center(
        child: Text('后续支持图片 / 文本智能识别', style: NewScheduleTextStyles.rowValue),
      ),
    );
  }
}

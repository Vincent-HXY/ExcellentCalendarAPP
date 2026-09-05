import 'package:flutter/material.dart';

import '../../../app/bootstrap/notification_permission_controller.dart';
import '../../../application/habit/habit_form_controller.dart';
import '../../../gateway_interfaces/category_repository.dart';
import '../../../gateway_interfaces/habit_gateway.dart';
import '../../../native_contract/habit/habit_response_dtos.dart';
import '../../category/category_picker_page.dart';
import '../../category/category_picker_result.dart';
import '../habit_design.dart';
import '../widgets/habit_page_components.dart';

class HabitFormPage extends StatefulWidget {
  const HabitFormPage({
    required this.gateway,
    required this.timezoneProvider,
    required this.categoryRepository,
    this.permissionController,
    this.initialDetail,
    this.initialStartDate,
    this.seed,
    this.onSubmitted,
    super.key,
  });
  final HabitGateway gateway;
  final String Function() timezoneProvider;
  final CategoryRepository categoryRepository;
  final NotificationPermissionController? permissionController;
  final HabitDetailResponseDto? initialDetail;
  final DateTime? initialStartDate;
  final HabitFormSeed? seed;
  final ValueChanged<HabitFormSubmitOutcome>? onSubmitted;

  @override
  State<HabitFormPage> createState() => _HabitFormPageState();
}

class _HabitFormPageState extends State<HabitFormPage> {
  late final HabitFormController _controller;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _target;
  late final TextEditingController _unit;

  @override
  void initState() {
    super.initState();
    _controller = HabitFormController(
      gateway: widget.gateway,
      timezoneProvider: widget.timezoneProvider,
      initialDetail: widget.initialDetail,
      initialStartDate: widget.initialStartDate,
      permissionController: widget.permissionController,
      seed: widget.seed,
    );
    _title = TextEditingController(text: _controller.title);
    _description = TextEditingController(text: _controller.description);
    _target = TextEditingController(text: _controller.targetText);
    _unit = TextEditingController(text: _controller.unit);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    _unit.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _controller.startDate : _controller.endDate;
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
      helpText: start ? '选择开始日期' : '选择结束日期',
      builder: (context, child) =>
          Theme(data: HabitDesign.pageTheme(context), child: child!),
    );
    if (value == null) return;
    start ? _controller.setStartDate(value) : _controller.setEndDate(value);
  }

  Future<void> _pickCategory() async {
    final result = await Navigator.of(context).push<CategoryPickerResult>(
      MaterialPageRoute(
        builder: (_) => CategoryPickerPage(
          repository: widget.categoryRepository,
          selectedCategoryId: _controller.categoryId,
        ),
      ),
    );
    if (result != null) _controller.setCategoryId(result.category?.id);
  }

  Future<void> _submit() async {
    final outcome = await _controller.submit();
    if (outcome == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => HabitDialog(
        title: const Text('习惯已保存'),
        content: Text(outcome.capabilityMessage),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    if (mounted) {
      widget.onSubmitted?.call(outcome);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => HabitPageScaffold(
    title: _controller.isEditing ? '编辑习惯' : '新建习惯',
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Column(
        children: [
          Expanded(child: _body()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: SizedBox(width: double.infinity, child: _submitButton()),
          ),
        ],
      ),
    ),
  );

  Widget _body() => SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section([
          const HabitSectionHeading(
            title: '从一件小事开始',
            subtitle: '把想要的改变，写进每一天。',
            icon: Icons.spa_outlined,
          ),
          TextField(
            controller: _title,
            maxLength: 80,
            onChanged: _controller.setTitle,
            decoration: InputDecoration(
              labelText: '习惯名称',
              hintText: '例如：每天读书 📚',
              errorText: _controller.errors['title'],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _description,
            maxLength: 2000,
            minLines: 2,
            maxLines: 3,
            onChanged: _controller.setDescription,
            decoration: InputDecoration(
              labelText: '描述（可选）',
              errorText: _controller.errors['description'],
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const HabitIconBadge(icon: Icons.label_outline_rounded),
            title: const Text('分类'),
            subtitle: Text(_controller.categoryId == null ? '未分类' : '已选择分类'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickCategory,
          ),
        ]),
        const SizedBox(height: 14),
        _section([
          const HabitSectionHeading(title: '每日目标', icon: Icons.flag_outlined),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              backgroundColor: HabitDesign.tint(context),
              selectedBackgroundColor: Theme.of(context).colorScheme.primary,
              selectedForegroundColor: Theme.of(context).colorScheme.onPrimary,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('完成型')),
              ButtonSegment(value: true, label: Text('数量型')),
            ],
            selected: {_controller.quantitative},
            onSelectionChanged: _controller.targetLocked
                ? null
                : (value) => _controller.setQuantitative(value.single),
          ),
          const SizedBox(height: 10),
          Text(
            _controller.quantitative
                ? '用数量记录积累，让每一点进步都看得见。'
                : '每天完成一次，轻轻一点就能打卡。',
            style: TextStyle(
              color: HabitDesign.muted(context),
              fontSize: 12,
              height: 1.6,
            ),
          ),
          if (_controller.targetLocked)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('首次打卡后，目标、单位和开始日期已锁定。'),
            ),
          if (_controller.quantitative) ...[
            const SizedBox(height: 10),
            _quantityFields(),
          ],
        ]),
        const SizedBox(height: 14),
        _section([
          const HabitSectionHeading(
            title: '挑战周期',
            subtitle: '选一个适合自己的节奏',
            icon: Icons.date_range_outlined,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _preset('7 天', HabitDurationPreset.days7),
              _preset('21 天', HabitDurationPreset.days21),
              _preset('30 天', HabitDurationPreset.days30),
              _preset('100 天', HabitDurationPreset.days100),
              _preset('1 个月', HabitDurationPreset.month1),
              _preset('3 个月', HabitDurationPreset.months3),
              _preset('1 年', HabitDurationPreset.year1),
            ],
          ),
          const SizedBox(height: 10),
          _dateTile(start: true),
          const Divider(),
          _dateTile(start: false),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HabitDesign.tint(context),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '最终结束日 ${formatHabitDate(_formatDate(_controller.endDate))} · '
              '共 ${_controller.plannedDays} 个计划日',
              style: TextStyle(
                color: _controller.errors.containsKey('dates')
                    ? Theme.of(context).colorScheme.error
                    : HabitDesign.muted(context),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _section([
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('每日提醒'),
            subtitle: const Text('在合适的时间，轻轻提醒你'),
            value: _controller.reminderEnabled,
            onChanged: _controller.setReminderEnabled,
          ),
          if (_controller.reminderEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const HabitIconBadge(icon: Icons.schedule_rounded),
              title: const Text('提醒时间'),
              subtitle: Text(_controller.reminderTime ?? '09:00'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final initial = _controller.reminderTime
                    ?.split(':')
                    .map(int.parse)
                    .toList();
                final time = await showTimePicker(
                  context: context,
                  builder: (context, child) => Theme(
                    data: HabitDesign.pageTheme(context),
                    child: child!,
                  ),
                  initialTime: TimeOfDay(
                    hour: initial?[0] ?? 9,
                    minute: initial?[1] ?? 0,
                  ),
                );
                if (time != null) {
                  _controller.setReminderTime(
                    '${time.hour.toString().padLeft(2, '0')}:'
                    '${time.minute.toString().padLeft(2, '0')}',
                  );
                }
              },
            ),
          if (_controller.capabilityMessage != null)
            Text(_controller.capabilityMessage!),
        ]),
        if (_controller.submitError != null) ...[
          const SizedBox(height: 14),
          Text(
            _controller.submitError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );

  Widget _submitButton() => FilledButton(
    onPressed: _controller.isSubmitting ? null : _submit,
    child: _controller.isSubmitting
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(_controller.isEditing ? '保存修改' : '开始挑战'),
  );

  Widget _section(List<Widget> children) => HabitSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _dateTile({required bool start}) {
    final locked = start && _controller.targetLocked;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: HabitIconBadge(
        icon: start ? Icons.today_outlined : Icons.event_available_outlined,
      ),
      title: Text(start ? '开始日期' : '结束日期'),
      subtitle: Text(
        formatHabitDate(
          _formatDate(start ? _controller.startDate : _controller.endDate),
        ),
      ),
      trailing: Icon(
        locked ? Icons.lock_outline_rounded : Icons.chevron_right_rounded,
      ),
      onTap: locked ? null : () => _pickDate(start: start),
    );
  }

  Widget _preset(String label, HabitDurationPreset preset) => ActionChip(
    label: Text(label),
    onPressed: () => _controller.applyPreset(preset),
  );

  Widget _quantityFields() => LayoutBuilder(
    builder: (context, constraints) {
      final target = TextField(
        controller: _target,
        enabled: !_controller.targetLocked,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: _controller.setTargetText,
        decoration: InputDecoration(
          labelText: '每日目标',
          errorText: _controller.errors['target'],
        ),
      );
      final unit = TextField(
        controller: _unit,
        enabled: !_controller.targetLocked,
        maxLength: 32,
        onChanged: _controller.setUnit,
        decoration: InputDecoration(
          labelText: '单位',
          errorText: _controller.errors['unit'],
        ),
      );
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth < 420 || textScale > 1.4) {
        return Column(children: [target, const SizedBox(height: 8), unit]);
      }
      return Row(
        children: [
          Expanded(child: target),
          const SizedBox(width: 12),
          Expanded(child: unit),
        ],
      );
    },
  );
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

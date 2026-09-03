import 'package:flutter/material.dart';

import '../../../application/category/category_models.dart';
import '../../../application/search/search_date_filter.dart';
import '../../../application/search/search_models.dart';
import '../../../native_contract/search/search_contract_enums.dart';
import '../../../native_contract/shared/civil_date.dart';
import '../search_design_tokens.dart';

Future<SearchFilters?> showSearchFilterPopover(
  BuildContext context, {
  required SearchState state,
  required VoidCallback onRetryCategories,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showGeneralDialog<SearchFilters>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭筛选',
    barrierColor: Colors.black54,
    transitionDuration: SearchDesignTokens.motion(context, 200),
    pageBuilder: (context, animation, secondaryAnimation) =>
        _SearchFilterPopover(
          initial: state.filters,
          today: state.today,
          categories: state.categories,
          categoryPhase: state.categoryLoadPhase,
          categoryError: state.categoryErrorMessage,
          onRetryCategories: onRetryCategories,
        ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class _SearchFilterPopover extends StatefulWidget {
  const _SearchFilterPopover({
    required this.initial,
    required this.today,
    required this.categories,
    required this.categoryPhase,
    required this.categoryError,
    required this.onRetryCategories,
  });
  final SearchFilters initial;
  final CivilDate today;
  final List<Category> categories;
  final SearchCategoryLoadPhase categoryPhase;
  final String? categoryError;
  final VoidCallback onRetryCategories;
  @override
  State<_SearchFilterPopover> createState() => _SearchFilterPopoverState();
}

class _SearchFilterPopoverState extends State<_SearchFilterPopover> {
  late SearchDateFilter _date;
  late Set<SearchTargetType> _types;
  late Set<String> _categoryIds;
  late bool _categoryFilterActive;
  late bool _uncategorized;
  late bool _includeCompleted;
  late SearchSortBy _sort;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
  }

  void _load(SearchFilters value) {
    _date = value.date;
    _types = value.targetTypes.toSet();
    _categoryFilterActive = value.categoryIds != null;
    _categoryIds = value.categoryIds?.toSet() ?? {};
    _uncategorized = value.includeUncategorized;
    _includeCompleted = value.includeCompleted;
    _sort = value.sortBy;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = (media.size.width - 32).clamp(0.0, 360.0);
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(
              SearchDesignTokens.popoverRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              height: (media.size.height - media.padding.vertical - 32).clamp(
                0.0,
                720.0,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
                    child: Row(
                      children: [
                        Text(
                          '筛选',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '关闭筛选',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _Section(
                          title: '时间',
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final preset in SearchDatePreset.values)
                                ChoiceChip(
                                  label: Text(_dateLabel(preset)),
                                  selected: _date.preset == preset,
                                  onSelected: (_) => _selectDate(preset),
                                ),
                            ],
                          ),
                        ),
                        _Section(
                          title: '类型',
                          error: _typeError,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              for (final type in SearchTargetType.values)
                                FilterChip(
                                  label: Text(_typeLabel(type)),
                                  selected: _types.contains(type),
                                  onSelected: (selected) => setState(() {
                                    final next = _types.toSet();
                                    selected
                                        ? next.add(type)
                                        : next.remove(type);
                                    if (next.isEmpty) {
                                      _typeError = '至少保留一种内容类型';
                                    } else {
                                      _types = next;
                                      _typeError = null;
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ),
                        _Section(title: '分类', child: _categoryBody()),
                        _Section(
                          title: '完成状态',
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('包含已完成内容'),
                            value: _includeCompleted,
                            onChanged: (value) =>
                                setState(() => _includeCompleted = value),
                          ),
                        ),
                        _Section(
                          title: '排序',
                          child: SegmentedButton<SearchSortBy>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: SearchSortBy.relevance,
                                label: Text('智能'),
                              ),
                              ButtonSegment(
                                value: SearchSortBy.occurTime,
                                label: Text('时间'),
                              ),
                              ButtonSegment(
                                value: SearchSortBy.updatedAt,
                                label: Text('更新'),
                              ),
                            ],
                            selected: {_sort},
                            onSelectionChanged: (value) =>
                                setState(() => _sort = value.single),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _load(SearchFilters())),
                          child: const Text('重置'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _apply,
                          child: const Text('查看结果'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryBody() {
    if (widget.categoryPhase == SearchCategoryLoadPhase.loading) {
      return const LinearProgressIndicator();
    }
    if (widget.categoryPhase == SearchCategoryLoadPhase.error) {
      return Row(
        children: [
          Expanded(child: Text(widget.categoryError ?? '分类加载失败')),
          TextButton(
            onPressed: () {
              widget.onRetryCategories();
              Navigator.pop(context);
            },
            child: const Text('重试'),
          ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('未分类'),
          selected: _categoryFilterActive && _uncategorized,
          onSelected: (value) => setState(() {
            _categoryFilterActive = value || _categoryIds.isNotEmpty;
            _uncategorized = value;
          }),
        ),
        for (final category in widget.categories)
          FilterChip(
            label: Text(category.name),
            selected:
                _categoryFilterActive && _categoryIds.contains(category.id),
            onSelected: (value) => setState(() {
              value
                  ? _categoryIds.add(category.id)
                  : _categoryIds.remove(category.id);
              _categoryFilterActive = _categoryIds.isNotEmpty || _uncategorized;
            }),
          ),
      ],
    );
  }

  Future<void> _selectDate(SearchDatePreset preset) async {
    if (preset != SearchDatePreset.custom) {
      setState(() => _date = SearchDateFilter.preset(preset, widget.today));
      return;
    }
    final initialFrom =
        _date.from?.toLocalDateTime() ?? widget.today.toLocalDateTime();
    final initialEnd =
        _date.toExclusive?.addDays(-1).toLocalDateTime() ?? initialFrom;
    final range = await _showAccessibleDateRangePicker(
      initialFrom: initialFrom,
      initialEnd: initialEnd,
      firstDate: DateTime(widget.today.year - 10),
      lastDate: DateTime(widget.today.year + 20, 12, 31),
    );
    if (range != null && mounted) {
      setState(
        () => _date = SearchDateFilter.custom(
          from: CivilDate.fromDateTime(range.start),
          toInclusive: CivilDate.fromDateTime(range.end),
        ),
      );
    }
  }

  Future<DateTimeRange?> _showAccessibleDateRangePicker({
    required DateTime initialFrom,
    required DateTime initialEnd,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    final start = await showDatePicker(
      context: context,
      initialDate: initialFrom,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: '选择开始日期',
      cancelText: '取消',
      confirmText: '下一步',
    );
    if (start == null || !mounted) {
      return null;
    }

    final end = await showDatePicker(
      context: context,
      initialDate: initialEnd.isBefore(start) ? start : initialEnd,
      firstDate: start,
      lastDate: lastDate,
      helpText: '选择结束日期',
      cancelText: '取消',
      confirmText: '保存',
    );
    if (end == null) {
      return null;
    }
    return DateTimeRange(start: start, end: end);
  }

  void _apply() {
    if (_types.isEmpty) {
      setState(() => _typeError = '至少保留一种内容类型');
      return;
    }
    Navigator.pop(
      context,
      SearchFilters(
        date: _date,
        targetTypes: _types,
        categoryIds: _categoryFilterActive
            ? _categoryIds.toList(growable: false)
            : null,
        includeUncategorized: _categoryFilterActive && _uncategorized,
        includeCompleted: _includeCompleted,
        sortBy: _sort,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.error});
  final String title;
  final Widget child;
  final String? error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

String _dateLabel(SearchDatePreset value) => switch (value) {
  SearchDatePreset.any => '不限',
  SearchDatePreset.today => '今天',
  SearchDatePreset.pastSevenDays => '过去 7 天',
  SearchDatePreset.nextSevenDays => '未来 7 天',
  SearchDatePreset.thisMonth => '本月',
  SearchDatePreset.custom => '自定义',
};
String _typeLabel(SearchTargetType value) => switch (value) {
  SearchTargetType.event => '日程',
  SearchTargetType.habit => '习惯',
  SearchTargetType.anniversary => '纪念日',
};

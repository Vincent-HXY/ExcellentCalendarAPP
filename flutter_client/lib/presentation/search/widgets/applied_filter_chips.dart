import 'package:flutter/material.dart';

import '../../../application/search/search_date_filter.dart';
import '../../../application/search/search_models.dart';
import '../../../native_contract/search/search_contract_enums.dart';

class AppliedFilterChips extends StatelessWidget {
  const AppliedFilterChips({
    required this.state,
    required this.onRemoveDate,
    required this.onRemoveCategories,
    required this.onRemoveTypes,
    required this.onRemoveCompletion,
    required this.onRemoveSort,
    super.key,
  });
  final SearchState state;
  final VoidCallback onRemoveDate;
  final VoidCallback onRemoveCategories;
  final VoidCallback onRemoveTypes;
  final VoidCallback onRemoveCompletion;
  final VoidCallback onRemoveSort;

  @override
  Widget build(BuildContext context) {
    if (state.filters.activeGroupCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (!state.filters.date.isDefault)
            InputChip(
              label: Text(_dateLabel(state.filters.date.preset)),
              onDeleted: onRemoveDate,
              deleteButtonTooltipMessage: '移除时间筛选',
            ),
          if (state.filters.targetTypes.length !=
              SearchTargetType.values.length)
            InputChip(
              label: Text(
                state.filters.orderedTargetTypes.map(_typeLabel).join('、'),
              ),
              onDeleted: onRemoveTypes,
              deleteButtonTooltipMessage: '移除类型筛选',
            ),
          if (state.filters.categoryIds != null)
            InputChip(
              label: const Text('分类'),
              onDeleted: onRemoveCategories,
              deleteButtonTooltipMessage: '移除分类筛选',
            ),
          if (!state.filters.includeCompleted)
            InputChip(
              label: const Text('仅未完成'),
              onDeleted: onRemoveCompletion,
              deleteButtonTooltipMessage: '移除完成状态筛选',
            ),
          if (state.filters.sortBy != SearchSortBy.relevance)
            InputChip(
              label: Text(_sortLabel(state.filters.sortBy)),
              onDeleted: onRemoveSort,
              deleteButtonTooltipMessage: '移除排序筛选',
            ),
        ],
      ),
    );
  }
}

String _dateLabel(SearchDatePreset value) => switch (value) {
  SearchDatePreset.any => '不限时间',
  SearchDatePreset.today => '今天',
  SearchDatePreset.pastSevenDays => '过去 7 天',
  SearchDatePreset.nextSevenDays => '未来 7 天',
  SearchDatePreset.thisMonth => '本月',
  SearchDatePreset.custom => '自定义时间',
};
String _typeLabel(SearchTargetType value) => switch (value) {
  SearchTargetType.event => '日程',
  SearchTargetType.habit => '习惯',
  SearchTargetType.anniversary => '纪念日',
};
String _sortLabel(SearchSortBy value) => switch (value) {
  SearchSortBy.relevance => '智能排序',
  SearchSortBy.occurTime => '时间最近',
  SearchSortBy.updatedAt => '最近更新',
};

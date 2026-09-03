import 'package:flutter/material.dart';

import '../../../application/search/search_models.dart';
import '../../../native_contract/search/search_contract_enums.dart';
import '../../../native_contract/search/search_response_dtos.dart';
import '../search_design_tokens.dart';
import 'search_result_row.dart';

class SearchSectionCard extends StatelessWidget {
  const SearchSectionCard({
    required this.state,
    required this.normalizedKeyword,
    required this.enabled,
    required this.onOpen,
    required this.onLoadMore,
    super.key,
  });
  final SearchSectionState state;
  final String normalizedKeyword;
  final bool enabled;
  final ValueChanged<SearchItemDto> onOpen;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = SearchTargetType.values.indexOf(state.type);
    final color = SearchDesignTokens.sectionColor(theme.colorScheme, index);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SearchDesignTokens.cardRadius),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_icon(state.type), color: color, size: 19),
                ),
                const SizedBox(width: 11),
                Text(
                  _title(state.type),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${state.totalCount} 条',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          for (var index = 0; index < state.items.length; index++) ...[
            SearchResultRow(
              item: state.items[index],
              normalizedKeyword: normalizedKeyword,
              enabled: enabled,
              onTap: () => onOpen(state.items[index]),
            ),
            if (index != state.items.length - 1)
              Divider(
                height: 1,
                indent: 18,
                endIndent: 18,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
          if (state.phase == SearchSectionPhase.loadingMore ||
              state.phase == SearchSectionPhase.refreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (state.phase == SearchSectionPhase.loadMoreError ||
              state.phase == SearchSectionPhase.contractError)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text(
                    state.errorMessage ?? '加载失败',
                    textAlign: TextAlign.center,
                  ),
                  if (state.phase == SearchSectionPhase.loadMoreError)
                    TextButton(onPressed: onLoadMore, child: const Text('重试')),
                ],
              ),
            )
          else if (state.hasMore)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: enabled ? onLoadMore : null,
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    '加载更多（已显示 ${state.items.length}/${state.totalCount}）',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _title(SearchTargetType type) => switch (type) {
  SearchTargetType.event => '日程',
  SearchTargetType.habit => '习惯',
  SearchTargetType.anniversary => '纪念日',
};

IconData _icon(SearchTargetType type) => switch (type) {
  SearchTargetType.event => Icons.event_note_rounded,
  SearchTargetType.habit => Icons.track_changes_rounded,
  SearchTargetType.anniversary => Icons.cake_outlined,
};

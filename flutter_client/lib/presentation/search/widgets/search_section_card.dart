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
    final palette = SearchPalette.of(context);
    final index = SearchTargetType.values.indexOf(state.type);
    final color = palette.sectionColor(theme.colorScheme, index);
    return Container(
      key: ValueKey('search-section-${state.type.wireValue}'),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SearchDesignTokens.cardRadius),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SearchDesignTokens.cardRadius),
        child: Material(
          color: palette.card,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: color),
              ),
              Column(
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
                          child: Icon(
                            _icon(state.type),
                            color: color,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Text(
                          '${_title(state.type)}（${state.totalCount}）',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  for (var index = 0; index < state.items.length; index++) ...[
                    SearchResultRow(
                      item: state.items[index],
                      normalizedKeyword: normalizedKeyword,
                      highlightColor: color,
                      enabled: enabled,
                      onTap: () => onOpen(state.items[index]),
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
                            TextButton(
                              onPressed: onLoadMore,
                              child: const Text('重试'),
                            ),
                        ],
                      ),
                    )
                  else if (state.hasMore)
                    Column(
                      children: [
                        Divider(
                          height: 1,
                          indent: SearchDesignTokens.resultContentIndent,
                          color: palette.divider,
                        ),
                        InkWell(
                          key: ValueKey(
                            'search-load-more-${state.type.wireValue}',
                          ),
                          onTap: enabled ? onLoadMore : null,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: SearchDesignTokens.loadMoreRowHeight,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: SearchDesignTokens.resultContentIndent,
                                right: SearchDesignTokens.resultRightPadding,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _remainingLabel(state),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
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

String _remainingLabel(SearchSectionState state) {
  final remaining = state.totalCount - state.items.length;
  return remaining > 0 ? '还有 $remaining 个${_title(state.type)}' : '加载更多';
}

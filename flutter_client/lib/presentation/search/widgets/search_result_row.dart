import 'package:flutter/material.dart';

import '../../../native_contract/search/search_contract_enums.dart';
import '../../../native_contract/search/search_response_dtos.dart';
import 'highlighted_search_text.dart';

class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    required this.item,
    required this.normalizedKeyword,
    required this.enabled,
    required this.onTap,
    super.key,
  });
  final SearchItemDto item;
  final String normalizedKeyword;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = item.match.snippet;
    final status = _status(item);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Semantics(
        button: true,
        enabled: enabled,
        label:
            '${item.title}，${_metadata(item)}${status == null ? '' : '，$status'}',
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HighlightedSearchText(
                        text: item.title,
                        normalizedKeyword: normalizedKeyword,
                        maxLines: 2,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _metadata(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (snippet != null) ...[
                        const SizedBox(height: 6),
                        HighlightedSearchText(
                          text: snippet.text,
                          normalizedKeyword: normalizedKeyword,
                          prefixTruncated: snippet.prefixTruncated,
                          suffixTruncated: snippet.suffixTruncated,
                          maxLines: 2,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (status != null) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(
                              _statusIcon(item),
                              size: 15,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              status,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _metadata(SearchItemDto item) {
  final category = item.category?.name;
  final detail = switch (item) {
    SearchEventItemDto value =>
      value.isAllDay
          ? '${value.occurDate} · 全天'
          : '${_dateTime(value.occurAt!)}${value.location == null ? '' : ' · ${value.location}'}',
    SearchHabitItemDto value =>
      '${value.occurDate} · 剩余 ${value.remainingDays} 天',
    SearchAnniversaryItemDto value =>
      '${value.occurDate} · ${_anniversaryRelation(value)}',
  };
  return category == null ? detail : '$detail · $category';
}

String? _status(SearchItemDto item) => switch (item) {
  SearchEventItemDto value => switch (value.status) {
    SearchEventStatus.pending => null,
    SearchEventStatus.inProgress => '进行中',
    SearchEventStatus.overdue => '已逾期',
    SearchEventStatus.completed => '已完成',
    SearchEventStatus.skipped => '已跳过',
  },
  SearchHabitItemDto value => switch (value.lifecycleStatus) {
    SearchHabitLifecycle.upcoming => '即将开始',
    SearchHabitLifecycle.active => null,
    SearchHabitLifecycle.completed => '已完成',
    SearchHabitLifecycle.endedEarly => '已提前结束',
  },
  SearchAnniversaryItemDto() => null,
};

IconData _statusIcon(SearchItemDto item) => switch (item) {
  SearchEventItemDto value when value.status == SearchEventStatus.completed =>
    Icons.check_circle_outline_rounded,
  SearchEventItemDto value when value.status == SearchEventStatus.skipped =>
    Icons.skip_next_rounded,
  SearchHabitItemDto value
      when value.lifecycleStatus == SearchHabitLifecycle.completed =>
    Icons.verified_outlined,
  _ => Icons.info_outline_rounded,
};

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

String _anniversaryRelation(SearchAnniversaryItemDto value) =>
    switch (value.relation) {
      SearchAnniversaryRelation.today => '就是今天',
      SearchAnniversaryRelation.remaining => '还有 ${value.days} 天',
      SearchAnniversaryRelation.elapsed => '已过 ${value.days} 天',
    };

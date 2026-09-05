import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../application/search/search_models.dart';
import '../search_design_tokens.dart';

class SearchHistoryCard extends StatelessWidget {
  const SearchHistoryCard({
    required this.state,
    required this.onSelected,
    required this.onEnterManaging,
    required this.onExitManaging,
    required this.onRemove,
    required this.onClear,
    required this.onUndo,
    required this.onRetry,
    super.key,
  });

  final SearchHistoryState state;
  final ValueChanged<String> onSelected;
  final VoidCallback onEnterManaging;
  final VoidCallback onExitManaging;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;
  final VoidCallback onUndo;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state.loadPhase == SearchHistoryLoadPhase.loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 72),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadPhase == SearchHistoryLoadPhase.error) {
      return _HistoryMessage(
        icon: Icons.history_toggle_off_rounded,
        message: state.errorMessage ?? '搜索历史暂时不可用',
        actionLabel: '重试',
        onAction: onRetry,
      );
    }
    if (state.items.isEmpty) {
      return Column(
        children: [
          const _HistoryMessage(
            icon: Icons.manage_search_rounded,
            message: '还没有搜索历史\n输入关键词开始查找',
          ),
          if (state.undoItems != null)
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const Expanded(child: Text('搜索历史已清空')),
                  TextButton(onPressed: onUndo, child: const Text('撤销')),
                ],
              ),
            ),
        ],
      );
    }
    final managing = state.mode == SearchHistoryMode.managing;
    final theme = Theme.of(context);
    final palette = SearchPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '最近搜索',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: managing ? onExitManaging : onClear,
              style: TextButton.styleFrom(
                textStyle: theme.textTheme.labelMedium,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(managing ? '完成' : '清空'),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 0,
          children: [
            for (final keyword in state.items)
              _HistoryChip(
                keyword: keyword,
                managing: managing,
                palette: palette,
                onTap: () => onSelected(keyword),
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  onEnterManaging();
                },
                onRemove: () => onRemove(keyword),
              ),
          ],
        ),
        if (state.writePhase == SearchHistoryWritePhase.writing)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (state.errorMessage != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        if (state.undoItems != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Expanded(child: Text('搜索历史已清空')),
                  TextButton(onPressed: onUndo, child: const Text('撤销')),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryChip extends StatelessWidget {
  const _HistoryChip({
    required this.keyword,
    required this.managing,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });
  final String keyword;
  final bool managing;
  final SearchPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final longClick = CustomSemanticsAction(label: '管理搜索历史');
    return Semantics(
      button: true,
      label: managing ? '$keyword，点按删除' : keyword,
      customSemanticsActions: managing ? null : {longClick: onLongPress},
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: managing ? onRemove : onTap,
        onLongPress: managing ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            key: ValueKey('search-history-chip-$keyword'),
            height: SearchDesignTokens.historyChipHeight,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(
              color: palette.historyChip,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.historyChipOutline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 152),
                  child: Text(
                    keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: SearchDesignTokens.historyChipFontSize,
                      color: palette.historyChipForeground,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (managing) ...[
                  const SizedBox(width: 5),
                  Tooltip(
                    message: '删除 $keyword',
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: palette.historyChipForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 72),
    child: Column(
      children: [
        Icon(
          icon,
          size: 42,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center),
        if (onAction != null) ...[
          const SizedBox(height: 14),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

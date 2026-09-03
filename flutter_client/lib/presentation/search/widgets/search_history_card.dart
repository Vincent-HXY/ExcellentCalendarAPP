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
    return Column(
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
              child: Text(managing ? '完成' : '清空'),
            ),
          ],
        ),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SearchDesignTokens.cardRadius),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < state.items.length; index++) ...[
                _HistoryRow(
                  keyword: state.items[index],
                  managing: managing,
                  onTap: () => onSelected(state.items[index]),
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    onEnterManaging();
                  },
                  onRemove: () => onRemove(state.items[index]),
                ),
                if (index != state.items.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: theme.colorScheme.outlineVariant,
                  ),
              ],
            ],
          ),
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

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.keyword,
    required this.managing,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });
  final String keyword;
  final bool managing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final longClick = CustomSemanticsAction(label: '管理搜索历史');
    return Semantics(
      customSemanticsActions: {longClick: onLongPress},
      child: InkWell(
        onTap: managing ? null : onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              const SizedBox(width: 18),
              const Icon(Icons.history_rounded, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  keyword,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AnimatedSwitcher(
                duration: SearchDesignTokens.motion(context, 160),
                child: managing
                    ? IconButton(
                        key: const ValueKey('delete'),
                        tooltip: '删除 $keyword',
                        onPressed: onRemove,
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      )
                    : const SizedBox(key: ValueKey('none'), width: 48),
              ),
            ],
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

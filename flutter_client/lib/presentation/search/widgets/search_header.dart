import 'package:flutter/material.dart';

import '../search_design_tokens.dart';

class SearchHeader extends StatelessWidget {
  const SearchHeader({
    required this.textController,
    required this.focusNode,
    required this.showLargeTitle,
    required this.filterCount,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onFilter,
    super.key,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool showLargeTitle;
  final int filterCount;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = SearchDesignTokens.motion(context, 220);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: showLargeTitle
              ? Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 18, left: 2),
                  child: Text(
                    '搜索',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : const SizedBox(height: 8),
        ),
        Row(
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: SearchDesignTokens.searchHeight,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(
                    SearchDesignTokens.searchRadius,
                  ),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: TextField(
                  key: const ValueKey('search-field'),
                  controller: textController,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.search,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  decoration: InputDecoration(
                    hintText: '搜索日程、习惯与纪念日',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: textController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除搜索',
                            onPressed: onClear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              label: filterCount == 0 ? '筛选' : '筛选，已启用 $filterCount 组条件',
              button: true,
              child: Badge(
                isLabelVisible: filterCount > 0,
                label: Text('$filterCount'),
                child: IconButton.filledTonal(
                  tooltip: '筛选',
                  onPressed: onFilter,
                  constraints: const BoxConstraints.tightFor(
                    width: SearchDesignTokens.minimumTouchTarget,
                    height: SearchDesignTokens.minimumTouchTarget,
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

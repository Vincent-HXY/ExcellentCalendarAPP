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
    final palette = SearchPalette.of(context);
    final duration = SearchDesignTokens.motion(
      context,
      SearchDesignTokens.headerMotionMilliseconds,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        AnimatedCrossFade(
          duration: duration,
          alignment: Alignment.topLeft,
          crossFadeState: showLargeTitle
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeInCubic,
          sizeCurve: Curves.easeInOutCubic,
          firstChild: Padding(
            padding: const EdgeInsets.only(bottom: 18, left: 2),
            child: Text(
              '搜索',
              key: const ValueKey('search-large-title'),
              style: theme.textTheme.headlineLarge?.copyWith(
                fontSize:
                    (theme.textTheme.headlineLarge?.fontSize ?? 32) *
                    SearchDesignTokens.titleScale,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          secondChild: const SizedBox.shrink(),
        ),
        Container(
          constraints: const BoxConstraints(
            minHeight: SearchDesignTokens.searchHeight,
          ),
          decoration: BoxDecoration(
            color: palette.searchField,
            borderRadius: BorderRadius.circular(
              SearchDesignTokens.searchRadius,
            ),
            border: Border.all(color: palette.outline),
            boxShadow: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
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
              suffixIconConstraints: const BoxConstraints(minHeight: 48),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (textController.text.isNotEmpty)
                    IconButton(
                      tooltip: '清除搜索',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  Semantics(
                    label: filterCount == 0 ? '筛选' : '筛选，已启用 $filterCount 组条件',
                    button: true,
                    child: Badge(
                      isLabelVisible: filterCount > 0,
                      label: Text('$filterCount'),
                      child: IconButton(
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
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

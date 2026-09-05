import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;

import '../../../app/routing/app_router.dart';
import '../../../application/search/search_controller.dart';
import '../../../application/search/search_models.dart';
import '../../../native_contract/search/search_contract_enums.dart';
import '../../../native_contract/search/search_response_dtos.dart';
import '../../../native_contract/search/search_text_contract.dart';
import '../search_design_tokens.dart';
import '../widgets/applied_filter_chips.dart';
import '../widgets/search_filter_popover.dart';
import '../widgets/search_header.dart';
import '../widgets/search_history_card.dart';
import '../widgets/search_section_card.dart';
import '../widgets/search_states.dart';

typedef SearchResultNavigator =
    Future<SearchDetailMutation> Function(
      BuildContext context,
      SearchItemDto item,
    );

class SearchPage extends StatefulWidget {
  const SearchPage({
    required this.controller,
    this.resultNavigator,
    this.disposeController = false,
    this.externallyManagedTabActivity = false,
    super.key,
  });
  final SearchController controller;
  final SearchResultNavigator? resultNavigator;
  final bool disposeController;
  final bool externallyManagedTabActivity;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textController = TextEditingController(
      text: widget.controller.state.rawKeyword,
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChanged);
    _scrollController = ScrollController();
    unawaited(
      widget.controller.initialize().then((_) async {
        await widget.controller.setAppLifecycleActive(true);
        if (!widget.externallyManagedTabActivity) {
          await widget.controller.setActive(true);
        }
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.setAppLifecycleActive(true));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.controller.setAppLifecycleActive(false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop:
          widget.controller.state.history.mode != SearchHistoryMode.managing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.controller.exitHistoryManaging();
      },
      child: Material(
        color: SearchPalette.of(context).background,
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final state = widget.controller.state;
              return LayoutBuilder(
                builder: (context, constraints) => Center(
                  child: SizedBox(
                    width: constraints.maxWidth.clamp(
                      0,
                      SearchDesignTokens.contentMaxWidth,
                    ),
                    child: CustomScrollView(
                      key: PageStorageKey(
                        'search-scroll-${state.scrollRestorationKey}',
                      ),
                      controller: _scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            constraints.maxWidth <= 380
                                ? SearchDesignTokens.compactPagePadding
                                : SearchDesignTokens.pagePadding,
                            0,
                            constraints.maxWidth <= 380
                                ? SearchDesignTokens.compactPagePadding
                                : SearchDesignTokens.pagePadding,
                            24 + MediaQuery.viewInsetsOf(context).bottom,
                          ),
                          sliver: SliverList.list(
                            children: [
                              SearchHeader(
                                textController: _textController,
                                focusNode: _focusNode,
                                showLargeTitle:
                                    SearchTextContract.isBlank(
                                      state.rawKeyword,
                                    ) &&
                                    !_focusNode.hasFocus,
                                filterCount: state.filters.activeGroupCount,
                                onChanged: _onTextChanged,
                                onSubmitted: (_) =>
                                    unawaited(widget.controller.submit()),
                                onClear: _clear,
                                onFilter: () => unawaited(_showFilters(state)),
                              ),
                              AppliedFilterChips(
                                state: state,
                                onRemoveDate: () => unawaited(
                                  widget.controller.removeDateFilter(),
                                ),
                                onRemoveCategories: () => unawaited(
                                  widget.controller.removeCategoryFilter(),
                                ),
                                onRemoveTypes: () => unawaited(
                                  widget.controller.removeTypeFilter(),
                                ),
                                onRemoveCompletion: () => unawaited(
                                  widget.controller.removeCompletionFilter(),
                                ),
                                onRemoveSort: () => unawaited(
                                  widget.controller.removeSortFilter(),
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (state.contentPhase ==
                                  SearchContentPhase.refreshing)
                                Semantics(
                                  liveRegion: true,
                                  label: '正在更新搜索结果',
                                  child: const LinearProgressIndicator(
                                    minHeight: 2,
                                  ),
                                ),
                              AnimatedSwitcher(
                                duration: SearchDesignTokens.motion(
                                  context,
                                  180,
                                ),
                                switchInCurve: Curves.easeOut,
                                switchOutCurve: Curves.easeOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, 0.02),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    '${state.contentPhase}-${state.displayedFingerprint}',
                                  ),
                                  child: _content(state),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _content(SearchState state) {
    if (SearchTextContract.isBlank(state.rawKeyword) ||
        state.contentPhase == SearchContentPhase.history) {
      return SearchHistoryCard(
        state: state.history,
        onSelected: _selectHistory,
        onEnterManaging: widget.controller.enterHistoryManaging,
        onExitManaging: widget.controller.exitHistoryManaging,
        onRemove: widget.controller.removeHistory,
        onClear: widget.controller.clearHistory,
        onUndo: widget.controller.undoClearHistory,
        onRetry: () => unawaited(widget.controller.retryHistory()),
      );
    }
    if (state.contentPhase == SearchContentPhase.debouncing) {
      return const SearchMessageState(
        icon: Icons.more_horiz_rounded,
        title: '继续输入',
        message: '停止输入 1 秒后自动搜索，也可以按键盘搜索键立即查找。',
      );
    }
    if (state.contentPhase == SearchContentPhase.initialLoading) {
      return const SearchLoadingSkeleton();
    }
    if (state.contentPhase == SearchContentPhase.error) {
      return SearchMessageState(
        icon: Icons.search_off_rounded,
        title: '搜索失败',
        message: state.errorMessage ?? '暂时无法搜索，请稍后重试。',
        actionLabel: '重试',
        onAction: () => unawaited(widget.controller.retry()),
      );
    }
    if (state.contentPhase == SearchContentPhase.empty) {
      return SearchMessageState(
        icon: Icons.inbox_outlined,
        title: '没有找到相关内容',
        message: state.filters.activeGroupCount > 0
            ? '可以清除筛选后再试一次。'
            : '换一个关键词再试试。',
        actionLabel: state.filters.activeGroupCount > 0 ? '清除筛选' : null,
        onAction: state.filters.activeGroupCount > 0
            ? () => unawaited(widget.controller.resetFilters())
            : null,
      );
    }
    return Column(
      children: [
        for (final type in SearchTargetType.values)
          if (state.section(type).items.isNotEmpty)
            SearchSectionCard(
              state: state.section(type),
              normalizedKeyword: state.normalizedKeyword,
              enabled: state.resultsInteractive,
              onOpen: _openResult,
              onLoadMore: () => unawaited(widget.controller.loadMore(type)),
            ),
        if (state.errorMessage != null && state.hasResults)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              state.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  void _onTextChanged(String value) {
    final composing = _textController.value.composing;
    widget.controller.updateText(
      value,
      isComposing: composing.isValid && !composing.isCollapsed,
    );
    setState(() {});
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  void _clear() {
    _textController.clear();
    widget.controller.clearKeyword();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _selectHistory(String keyword) {
    _textController.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(offset: keyword.length),
    );
    setState(() {});
    unawaited(widget.controller.selectHistory(keyword));
  }

  Future<void> _showFilters(SearchState state) async {
    final filters = await showSearchFilterPopover(
      context,
      state: state,
      onRetryCategories: () => unawaited(widget.controller.retryCategories()),
    );
    if (filters != null) await widget.controller.applyFilters(filters);
  }

  Future<void> _openResult(SearchItemDto item) async {
    if (!widget.controller.state.resultsInteractive) return;
    widget.controller.recordOpenedResult();
    final navigator = widget.resultNavigator ?? _defaultNavigate;
    final mutation = await navigator(context, item);
    if (!mounted) return;
    await widget.controller.refreshAfterDetail(item.targetType, mutation);
  }

  Future<SearchDetailMutation> _defaultNavigate(
    BuildContext context,
    SearchItemDto item,
  ) async {
    final route = _detailRoute(item);
    final result = await Navigator.of(context).pushNamed<Object?>(route);
    return switch (result) {
      ContentDetailRouteOutcome.changed => SearchDetailMutation.changed,
      ContentDetailRouteOutcome.deleted => SearchDetailMutation.deleted,
      true => SearchDetailMutation.changed,
      _ => SearchDetailMutation.unchanged,
    };
  }

  String _detailRoute(SearchItemDto item) {
    final query = switch (item) {
      SearchEventItemDto value => <String, String>{
        if (value.occurrenceKey != null) 'occurrence_key': value.occurrenceKey!,
        if (value.recurrenceRevision != null)
          'recurrence_revision': '${value.recurrenceRevision}',
        if (value.occurAt != null)
          'occurrence_start_at': _wholeSecondUtc(value.occurAt!),
        if (value.occurDate != null) 'occurrence_start_date': value.occurDate!,
      },
      SearchHabitItemDto value => <String, String>{
        'selected_date': value.occurDate,
      },
      SearchAnniversaryItemDto value => <String, String>{
        'occurrence_key': value.occurrenceKey,
        'occurrence_date': value.occurDate,
      },
    };
    final base =
        '/${item.targetType.wireValue}/detail/${Uri.encodeComponent(item.targetId)}';
    final encoded = Uri(queryParameters: query).query;
    return encoded.isEmpty ? base : '$base?$encoded';
  }

  String _wholeSecondUtc(DateTime value) {
    final utc = value.toUtc();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.controller.setAppLifecycleActive(false));
    if (!widget.externallyManagedTabActivity) {
      unawaited(widget.controller.setActive(false));
    }
    _textController.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _scrollController.dispose();
    if (widget.disposeController) widget.controller.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/category/category_list_controller.dart';
import '../../application/category/category_models.dart';
import '../../gateway_interfaces/category_repository.dart';
import 'category_design_tokens.dart';
import 'category_picker_result.dart';
import 'create_category_page.dart';

class CategoryPickerPage extends StatefulWidget {
  const CategoryPickerPage({
    required this.repository,
    required this.selectedCategoryId,
    super.key,
  });

  final CategoryRepository repository;
  final String? selectedCategoryId;

  @override
  State<CategoryPickerPage> createState() => _CategoryPickerPageState();
}

class _CategoryPickerPageState extends State<CategoryPickerPage> {
  late final CategoryListController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CategoryListController(widget.repository);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCreatePage() async {
    final created = await Navigator.of(context).push<Category>(
      MaterialPageRoute<Category>(
        builder: (_) => CreateCategoryPage(repository: widget.repository),
      ),
    );
    if (!mounted || created == null) {
      return;
    }
    _controller.addCreatedCategory(created);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: CategoryColors.pageBackground,
      ),
      child: Scaffold(
        backgroundColor: CategoryColors.pageBackground,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryTopBar(onAdd: _openCreatePage),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CategorySpacing.pageHorizontal,
            16,
            CategorySpacing.pageHorizontal,
            CategorySpacing.cardGap,
          ),
          child: _UnclassifiedCategoryCard(
            selected: widget.selectedCategoryId == null,
            onTap: () => Navigator.of(
              context,
            ).pop(const CategoryPickerResult.unclassified()),
          ),
        ),
        Expanded(
          child: switch (_controller.phase) {
            CategoryListPhase.loading => const Center(
              child: CircularProgressIndicator(color: CategoryColors.accent),
            ),
            CategoryListPhase.empty => _CategoryStatusView(
              key: const ValueKey('category-empty-state'),
              message: '暂无自定义分类，可选择未分类或点击右上角添加',
              actionLabel: '添加分类',
              onAction: _openCreatePage,
            ),
            CategoryListPhase.error => _CategoryStatusView(
              key: const ValueKey('category-error-state'),
              message: _controller.errorMessage ?? '分类加载失败',
              actionLabel: '重试',
              onAction: _controller.load,
            ),
            CategoryListPhase.ready => ListView.separated(
              key: const ValueKey('category-list'),
              padding: const EdgeInsets.fromLTRB(
                CategorySpacing.pageHorizontal,
                0,
                CategorySpacing.pageHorizontal,
                CategorySpacing.bottom,
              ),
              itemCount: _controller.categories.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: CategorySpacing.cardGap),
              itemBuilder: (context, index) {
                final category = _controller.categories[index];
                return _CategoryListCard(
                  key: ValueKey('category-card-${category.id}'),
                  category: category,
                  selected: category.id == widget.selectedCategoryId,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(CategoryPickerResult.category(category)),
                );
              },
            ),
          },
        ),
      ],
    );
  }
}

class _UnclassifiedCategoryCard extends StatelessWidget {
  const _UnclassifiedCategoryCard({
    required this.selected,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '未分类，${selected ? '已选中' : '未选中'}',
      child: Material(
        key: const ValueKey('category-card-unclassified'),
        color: CategoryColors.surface,
        borderRadius: BorderRadius.circular(CategorySizes.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CategorySizes.listCardMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CategorySpacing.cardHorizontal,
                vertical: 10,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.label_off_outlined,
                    size: 19,
                    color: CategoryColors.secondaryText,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      '未分类',
                      style: TextStyle(
                        color: CategoryColors.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _SelectionIndicator(
                    indicatorKey: const ValueKey(
                      'category-selection-unclassified',
                    ),
                    selected: selected,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryTopBar extends StatelessWidget {
  const _CategoryTopBar({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CategorySizes.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('category-back-button'),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: CategoryColors.primaryText,
                size: 30,
              ),
            ),
            const Expanded(
              child: Text(
                '日历分类',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CategoryColors.primaryText,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('category-add-button'),
              tooltip: '添加分类',
              onPressed: onAdd,
              icon: const Icon(
                Icons.add_rounded,
                color: CategoryColors.primaryText,
                size: 34,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryListCard extends StatelessWidget {
  const _CategoryListCard({
    required this.category,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '分类 ${category.name}，${selected ? '已选中' : '未选中'}',
      child: Material(
        color: CategoryColors.surface,
        borderRadius: BorderRadius.circular(CategorySizes.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CategorySizes.listCardMinHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CategorySpacing.cardHorizontal,
                vertical: 10,
              ),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: categoryColorFromHex(category.color),
                    ),
                    child: const SizedBox.square(dimension: 15),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CategoryColors.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _SelectionIndicator(
                    indicatorKey: ValueKey('category-selection-${category.id}'),
                    selected: selected,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected, this.indicatorKey});

  final bool selected;
  final Key? indicatorKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: indicatorKey,
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected
              ? CategoryColors.accent
              : CategoryColors.selectionIdle,
          width: selected ? 4 : 2,
        ),
      ),
    );
  }
}

class _CategoryStatusView extends StatelessWidget {
  const _CategoryStatusView({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(CategorySpacing.pageHorizontal),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CategoryColors.surface,
            borderRadius: BorderRadius.circular(CategorySizes.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CategoryColors.secondaryText,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: CategoryColors.accent,
                    minimumSize: const Size(96, 48),
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

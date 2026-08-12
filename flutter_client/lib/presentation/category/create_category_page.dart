import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/category/category_models.dart';
import '../../application/category/create_category_controller.dart';
import '../../gateway_interfaces/category_repository.dart';
import 'category_design_tokens.dart';

class CreateCategoryPage extends StatefulWidget {
  const CreateCategoryPage({required this.repository, super.key});

  final CategoryRepository repository;

  @override
  State<CreateCategoryPage> createState() => _CreateCategoryPageState();
}

class _CreateCategoryPageState extends State<CreateCategoryPage> {
  late final CreateCategoryController _controller;
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = CreateCategoryController(widget.repository);
    _nameController.addListener(_handleNameChanged);
    _descriptionController.addListener(_handleDescriptionChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_handleNameChanged);
    _descriptionController.removeListener(_handleDescriptionChanged);
    _nameController.dispose();
    _descriptionController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleNameChanged() => _controller.setName(_nameController.text);

  void _handleDescriptionChanged() =>
      _controller.setDescription(_descriptionController.text);

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final created = await _controller.submit();
    if (!mounted || created == null) {
      return;
    }
    Navigator.of(context).pop<Category>(created);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: CategoryColors.pageBackground,
      ),
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => PopScope(
          canPop: !_controller.isSubmitting,
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: CategoryColors.pageBackground,
            body: SafeArea(
              child: Column(
                children: [
                  _CreateCategoryTopBar(
                    canSubmit: _controller.canSubmit,
                    isSubmitting: _controller.isSubmitting,
                    onCancel: () => Navigator.of(context).maybePop(),
                    onSubmit: _submit,
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          CategorySpacing.pageHorizontal,
                          10,
                          CategorySpacing.pageHorizontal,
                          CategorySpacing.bottom +
                              MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _CategoryTextFieldCard(
                              key: const ValueKey('category-name-card'),
                              controller: _nameController,
                              fieldKey: const ValueKey('category-name-field'),
                              hintText: '分类名称',
                              autofocus: true,
                              maxLength: 40,
                              maxLines: 1,
                              textInputAction: TextInputAction.next,
                              errorText: _controller.nameError,
                            ),
                            const SizedBox(height: CategorySpacing.sectionGap),
                            _CategoryTextFieldCard(
                              key: const ValueKey('category-description-card'),
                              controller: _descriptionController,
                              fieldKey: const ValueKey(
                                'category-description-field',
                              ),
                              hintText: '备注',
                              maxLength: 200,
                              minLines: 2,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              errorText: _controller.descriptionError,
                            ),
                            const SizedBox(height: CategorySpacing.sectionGap),
                            _ColorPickerCard(
                              selectedColor: _controller.selectedColor,
                              onSelected: _controller.selectColor,
                            ),
                            if (_controller.submitError != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _controller.submitError!,
                                key: const ValueKey('category-submit-error'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: CategoryColors.error,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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

class _CreateCategoryTopBar extends StatelessWidget {
  const _CreateCategoryTopBar({
    required this.canSubmit,
    required this.isSubmitting,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool canSubmit;
  final bool isSubmitting;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: CategorySizes.topBarHeight,
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: TextButton(
              key: const ValueKey('category-cancel-button'),
              onPressed: isSubmitting ? null : onCancel,
              style: TextButton.styleFrom(
                foregroundColor: CategoryColors.accent,
                disabledForegroundColor: CategoryColors.secondaryText,
                minimumSize: const Size(
                  CategorySizes.minTapTarget,
                  CategorySizes.minTapTarget,
                ),
              ),
              child: const Text(
                '取消',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Expanded(
            child: Text(
              '添加分类',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CategoryColors.primaryText,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 82,
            child: TextButton(
              key: const ValueKey('category-submit-button'),
              onPressed: canSubmit ? onSubmit : null,
              style: TextButton.styleFrom(
                foregroundColor: CategoryColors.accent,
                disabledForegroundColor: CategoryColors.secondaryText,
                minimumSize: const Size(
                  CategorySizes.minTapTarget,
                  CategorySizes.minTapTarget,
                ),
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: CategoryColors.accent,
                      ),
                    )
                  : const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTextFieldCard extends StatelessWidget {
  const _CategoryTextFieldCard({
    required this.controller,
    required this.fieldKey,
    required this.hintText,
    required this.maxLength,
    required this.maxLines,
    required this.textInputAction,
    this.autofocus = false,
    this.minLines,
    this.errorText,
    super.key,
  });

  final TextEditingController controller;
  final Key fieldKey;
  final String hintText;
  final int maxLength;
  final int? minLines;
  final int maxLines;
  final TextInputAction textInputAction;
  final bool autofocus;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CategoryColors.surface,
        borderRadius: BorderRadius.circular(CategorySizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        child: TextField(
          key: fieldKey,
          controller: controller,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          textInputAction: textInputAction,
          style: const TextStyle(
            color: CategoryColors.primaryText,
            fontSize: 18,
            height: 1.35,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hintText,
            hintStyle: const TextStyle(
              color: CategoryColors.secondaryText,
              fontSize: 18,
              fontWeight: FontWeight.w400,
            ),
            counterText: '',
            errorText: errorText,
            errorStyle: const TextStyle(
              color: CategoryColors.error,
              fontSize: 12,
            ),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

class _ColorPickerCard extends StatelessWidget {
  const _ColorPickerCard({
    required this.selectedColor,
    required this.onSelected,
  });

  final String? selectedColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CategoryColors.surface,
        borderRadius: BorderRadius.circular(CategorySizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '颜色',
              style: TextStyle(
                color: CategoryColors.primaryText,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 20,
              runSpacing: 18,
              children: [
                for (final option in categoryColorOptions)
                  _ColorChoice(
                    option: option,
                    selected: selectedColor == option.hex,
                    onTap: () => onSelected(option.hex),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CategoryColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}，${selected ? '已选中' : '未选中'}',
      child: InkResponse(
        key: ValueKey('category-color-${option.hex}'),
        onTap: onTap,
        radius: CategorySizes.colorTapTarget / 2,
        containedInkWell: true,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: CategorySizes.colorTapTarget,
          child: DecoratedBox(
            decoration: selected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: option.color, width: 3),
                  )
                : const BoxDecoration(shape: BoxShape.circle),
            child: Padding(
              padding: EdgeInsets.all(selected ? 5 : 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: option.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

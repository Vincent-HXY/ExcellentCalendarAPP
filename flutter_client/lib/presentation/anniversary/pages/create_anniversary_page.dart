import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/anniversary/app_clock.dart';
import '../../../application/anniversary/anniversary_form_controller.dart';
import '../../../application/anniversary/anniversary_models.dart';
import '../../../gateway_interfaces/anniversary_gateway.dart';
import '../anniversary_design_tokens.dart';
import '../widgets/anniversary_form_fields.dart';
import '../widgets/anniversary_form_preview_card.dart';

class CreateAnniversaryPage extends StatefulWidget {
  const CreateAnniversaryPage({
    required this.gateway,
    required this.clock,
    this.initialDetail,
    super.key,
  });

  final AnniversaryGateway gateway;
  final AppClock clock;
  final AnniversaryDetail? initialDetail;

  @override
  State<CreateAnniversaryPage> createState() => _CreateAnniversaryPageState();
}

class _CreateAnniversaryPageState extends State<CreateAnniversaryPage> {
  final _formKey = GlobalKey<FormState>();
  late final AnniversaryFormController _controller;
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _controller = AnniversaryFormController(
      gateway: widget.gateway,
      initialDetail: widget.initialDetail,
    );
    _titleController = TextEditingController(text: _controller.title);
    _noteController = TextEditingController(text: _controller.note);
    _controller.initialize();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final currentDate = anniversaryDateOnly(widget.clock.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _controller.date ?? currentDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      currentDate: currentDate,
      helpText: '选择纪念日日期',
      cancelText: '取消',
      confirmText: '确定',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: AnniversaryColors.primaryTeal),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) {
      return;
    }
    _controller.setDate(selected);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await _controller.submit();
    if (!mounted) {
      return;
    }
    _formKey.currentState?.validate();
    if (result != null) {
      Navigator.of(context).pop(result);
      return;
    }
    final error = _controller.submitError;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AnniversaryColors.listBackground,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AnniversaryColors.listBackground,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              children: [
                _FormTopBar(
                  isEditing: _controller.isEditing,
                  isSubmitting: _controller.isSubmitting,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        AnniversarySpacing.pageHorizontal,
                        4,
                        AnniversarySpacing.pageHorizontal,
                        AnniversarySpacing.formBottom +
                            MediaQuery.viewInsetsOf(context).bottom,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AnniversaryFormPreviewCard(
                              title: _controller.title,
                              preview: _controller.preview,
                              phase: _controller.previewPhase,
                              calendarType: _controller.calendarType,
                            ),
                            const SizedBox(
                              height: AnniversarySpacing.sectionGap,
                            ),
                            AnniversaryFormFields(
                              controller: _controller,
                              titleController: _titleController,
                              noteController: _noteController,
                              onPickDate: _pickDate,
                            ),
                            if (_controller.submitError != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _controller.submitError!,
                                key: const ValueKey('anniversary-submit-error'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AnniversaryColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 56,
                              child: FilledButton(
                                key: const ValueKey('anniversary-save-button'),
                                onPressed: _controller.isSubmitting
                                    ? null
                                    : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      AnniversaryColors.primaryTeal,
                                  disabledBackgroundColor: AnniversaryColors
                                      .primaryTeal
                                      .withValues(alpha: 0.5),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: _controller.isSubmitting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _controller.isEditing
                                            ? '保存修改'
                                            : '保存纪念日',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormTopBar extends StatelessWidget {
  const _FormTopBar({
    required this.isEditing,
    required this.isSubmitting,
    required this.onBack,
  });

  final bool isEditing;
  final bool isSubmitting;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: isSubmitting ? null : onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              isEditing ? '编辑纪念日' : '新建纪念日',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AnniversaryColors.primaryText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AnniversarySizes.minTapTarget),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/change_password_controller.dart';
import '../../auth/auth_design_tokens.dart';
import '../../auth/widgets/auth_card.dart';
import '../../auth/widgets/auth_form_fields.dart';
import '../../auth/widgets/auth_page_scaffold.dart';
import '../../auth/widgets/auth_submit_button.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({
    required this.authService,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final AuthNavigator navigator;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  late final ChangePasswordController _controller;
  final TextEditingController _current = TextEditingController();
  final TextEditingController _new = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ChangePasswordController(widget.authService);
  }

  @override
  void dispose() {
    _controller.dispose();
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (!mounted) return;
    switch (outcome) {
      case ChangePasswordOutcome.changed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改，当前设备保持登录')));
        Navigator.of(context).pop();
      case ChangePasswordOutcome.sessionEnded:
        widget.navigator.goToLogin();
      case ChangePasswordOutcome.failed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '修改密码',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                '修改成功后其他设备将被登出，当前设备保持登录',
                style: AuthDesignTokens.hintTextStyle,
              ),
              const SizedBox(height: 16),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthTextField(
                      label: '当前密码',
                      controller: _current,
                      errorText: _controller.currentPasswordError,
                      obscureText: _controller.obscureCurrent,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setCurrentPassword,
                      suffix: ObscureToggle(
                        obscure: _controller.obscureCurrent,
                        onPressed: _controller.toggleObscureCurrent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '新密码（至少 8 个字符）',
                      controller: _new,
                      errorText: _controller.newPasswordError,
                      obscureText: _controller.obscureNew,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setNewPassword,
                      suffix: ObscureToggle(
                        obscure: _controller.obscureNew,
                        onPressed: _controller.toggleObscureNew,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '确认新密码',
                      controller: _confirm,
                      errorText: _controller.confirmPasswordError,
                      obscureText: _controller.obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onChanged: _controller.setConfirmPassword,
                      onSubmitted: (_) => _submit(),
                      suffix: ObscureToggle(
                        obscure: _controller.obscureConfirm,
                        onPressed: _controller.toggleObscureConfirm,
                      ),
                    ),
                    if (_controller.formError != null) ...[
                      const SizedBox(height: 14),
                      AuthFormErrorBanner(message: _controller.formError!),
                    ],
                    const SizedBox(height: 20),
                    AuthSubmitButton(
                      label: '修改密码',
                      loading: _controller.isSubmitting,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

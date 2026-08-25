import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/reset_password_controller.dart';
import '../auth_design_tokens.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_form_fields.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/auth_submit_button.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({
    required this.authService,
    required this.navigator,
    required this.onResetSucceeded,
    super.key,
  });

  final AuthService authService;
  final AuthNavigator navigator;

  /// Clears the local session (AT, Android Refresh Token) after success.
  final Future<void> Function() onResetSucceeded;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  ResetPasswordController? _controller;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  ResetPasswordController get controller => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final arguments =
        ModalRoute.of(context)?.settings.arguments
            as ResetPasswordPageArguments?;
    final controller = ResetPasswordController(
      widget.authService.authGateway,
      onResetSucceeded: widget.onResetSucceeded,
      initialEmail: arguments?.email ?? '',
    );
    _controller = controller;
    _email.text = controller.email;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await controller.submit();
    if (!mounted) return;
    if (outcome == ResetPasswordOutcome.reset) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码已重置，请用新密码登录')));
      widget.navigator.goToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '重置密码',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('设置新密码', style: AuthDesignTokens.pageTitleStyle),
              const SizedBox(height: 6),
              const Text(
                '输入邮箱收到的验证码并设置新密码',
                style: AuthDesignTokens.hintTextStyle,
              ),
              const SizedBox(height: 20),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthTextField(
                      label: '邮箱',
                      controller: _email,
                      errorText: controller.emailError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: controller.setEmail,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '验证码',
                      controller: _code,
                      errorText: controller.codeError,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textInputAction: TextInputAction.next,
                      onChanged: controller.setCode,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '新密码（至少 8 个字符）',
                      controller: _password,
                      errorText: controller.newPasswordError,
                      obscureText: controller.obscureNew,
                      textInputAction: TextInputAction.next,
                      onChanged: controller.setNewPassword,
                      suffix: ObscureToggle(
                        obscure: controller.obscureNew,
                        onPressed: controller.toggleObscureNew,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '确认新密码',
                      controller: _confirm,
                      errorText: controller.confirmPasswordError,
                      obscureText: controller.obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onChanged: controller.setConfirmPassword,
                      onSubmitted: (_) => _submit(),
                      suffix: ObscureToggle(
                        obscure: controller.obscureConfirm,
                        onPressed: controller.toggleObscureConfirm,
                      ),
                    ),
                    if (controller.formError != null) ...[
                      const SizedBox(height: 14),
                      AuthFormErrorBanner(message: controller.formError!),
                    ],
                    const SizedBox(height: 20),
                    AuthSubmitButton(
                      label: '重置密码',
                      loading: controller.isSubmitting,
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

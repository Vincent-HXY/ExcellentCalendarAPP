import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/email_verification_controller.dart';
import '../../../application/auth/register_controller.dart';
import '../auth_design_tokens.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_form_fields.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/auth_submit_button.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    required this.authService,
    required this.localeProvider,
    required this.timezoneProvider,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final String Function() localeProvider;
  final Future<String> Function() timezoneProvider;
  final AuthNavigator navigator;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late final RegisterController _controller;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = RegisterController(
      widget.authService.authGateway.register,
      localeProvider: widget.localeProvider,
      timezoneProvider: widget.timezoneProvider,
    );
    _controller.prepareDefaults();
  }

  @override
  void dispose() {
    _controller.dispose();
    _email.dispose();
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (!mounted) return;
    final pending = _controller.pending;
    if (outcome == RegisterOutcome.registered && pending != null) {
      widget.navigator.goToVerification(
        VerificationPageArguments(
          challenge: pending.challenge,
          mode: EmailVerificationMode.registration,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '注册',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('创建账号', style: AuthDesignTokens.pageTitleStyle),
              const SizedBox(height: 6),
              const Text('注册后需验证邮箱才能登录', style: AuthDesignTokens.hintTextStyle),
              const SizedBox(height: 20),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthTextField(
                      label: '邮箱',
                      controller: _email,
                      errorText: _controller.emailError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setEmail,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '用户名（3-24 位小写字母/数字/下划线）',
                      controller: _username,
                      errorText: _controller.usernameError,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setUsername,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '昵称',
                      controller: _displayName,
                      errorText: _controller.displayNameError,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setDisplayName,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '密码（至少 8 个字符）',
                      controller: _password,
                      errorText: _controller.passwordError,
                      obscureText: _controller.obscurePassword,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setPassword,
                      suffix: ObscureToggle(
                        obscure: _controller.obscurePassword,
                        onPressed: _controller.toggleObscurePassword,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '确认密码',
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
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _controller.agreementAccepted,
                          onChanged: (value) =>
                              _controller.setAgreementAccepted(value ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            '我已阅读并同意《用户协议》（占位）',
                            style: TextStyle(
                              fontSize: 13,
                              color: AuthDesignTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_controller.formError != null) ...[
                      const SizedBox(height: 10),
                      AuthFormErrorBanner(message: _controller.formError!),
                    ],
                    const SizedBox(height: 16),
                    AuthSubmitButton(
                      label: '注册',
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

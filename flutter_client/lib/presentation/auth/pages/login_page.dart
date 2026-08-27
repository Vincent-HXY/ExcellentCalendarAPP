import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/email_verification_controller.dart';
import '../../../application/auth/login_controller.dart';
import '../auth_design_tokens.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_form_fields.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/auth_submit_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.authService,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final AuthNavigator navigator;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final LoginController _controller;
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = LoginController(widget.authService);
  }

  @override
  void dispose() {
    _controller.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (!mounted) return;
    if (outcome == LoginOutcome.failed) {
      // 登录失败保留邮箱、清空密码输入。
      _password.clear();
    }
    switch (outcome) {
      case LoginOutcome.authenticated:
        widget.navigator.goToHome();
      case LoginOutcome.verificationRequired:
        final challenge = _controller.verificationChallenge;
        if (challenge == null) return;
        widget.navigator.goToVerification(
          VerificationPageArguments(
            challenge: challenge,
            mode: EmailVerificationMode.registration,
          ),
        );
      case LoginOutcome.failed:
        // Keep this page alive so the inline error and email remain visible.
        return;
      case LoginOutcome.sessionEnded:
        widget.navigator.goToLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '登录',
      showBack: false,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('欢迎回来', style: AuthDesignTokens.pageTitleStyle),
              const SizedBox(height: 6),
              const Text(
                '登录后可同步你的日程与个人资料',
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
                      errorText: _controller.emailError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setEmail,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '密码',
                      controller: _password,
                      errorText: _controller.passwordError,
                      obscureText: _controller.obscurePassword,
                      textInputAction: TextInputAction.done,
                      onChanged: _controller.setPassword,
                      onSubmitted: (_) => _submit(),
                      suffix: ObscureToggle(
                        obscure: _controller.obscurePassword,
                        onPressed: _controller.toggleObscurePassword,
                      ),
                    ),
                    if (_controller.formError != null) ...[
                      const SizedBox(height: 14),
                      AuthFormErrorBanner(message: _controller.formError!),
                    ],
                    const SizedBox(height: 20),
                    AuthSubmitButton(
                      label: '登录',
                      loading: _controller.isSubmitting,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _controller.isSubmitting
                        ? null
                        : () => widget.navigator.push('/register'),
                    child: const Text(
                      '注册新账号',
                      style: TextStyle(
                        color: AuthDesignTokens.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _controller.isSubmitting
                        ? null
                        : () => widget.navigator.push('/forgot-password'),
                    child: const Text(
                      '忘记密码？',
                      style: TextStyle(
                        color: AuthDesignTokens.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

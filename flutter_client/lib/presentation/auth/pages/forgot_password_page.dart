import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/forgot_password_controller.dart';
import '../../../application/auth/auth_messages.dart';
import '../auth_design_tokens.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_form_fields.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/auth_submit_button.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    required this.authService,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final AuthNavigator navigator;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  late final ForgotPasswordController _controller;
  final TextEditingController _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ForgotPasswordController(widget.authService.authGateway);
  }

  @override
  void dispose() {
    _controller.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _controller.submit();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '忘记密码',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('重置你的密码', style: AuthDesignTokens.pageTitleStyle),
              const SizedBox(height: 6),
              const Text(
                '输入注册邮箱，我们会发送验证码',
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
                      textInputAction: TextInputAction.done,
                      onChanged: _controller.setEmail,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_controller.wasSent) ...[
                      const SizedBox(height: 14),
                      AuthInfoBanner(message: forgotPasswordSuccessMessage),
                    ],
                    if (_controller.formError != null) ...[
                      const SizedBox(height: 14),
                      AuthFormErrorBanner(message: _controller.formError!),
                    ],
                    const SizedBox(height: 20),
                    if (!_controller.wasSent)
                      AuthSubmitButton(
                        label: '发送验证码',
                        loading: _controller.isSubmitting,
                        onPressed: _submit,
                      )
                    else ...[
                      AuthSubmitButton(
                        label: '前往重置密码',
                        onPressed: () => widget.navigator.pushResetPassword(
                          ResetPasswordPageArguments(
                            email: _controller.email.trim(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _controller.canResend ? _submit : null,
                          child: Text(
                            _controller.canResend
                                ? '重新发送验证码'
                                : '重新发送（${_controller.resendSecondsRemaining}s）',
                            style: const TextStyle(
                              color: AuthDesignTokens.primary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
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

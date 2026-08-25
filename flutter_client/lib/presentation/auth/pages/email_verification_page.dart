import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/email_verification_controller.dart';
import '../auth_design_tokens.dart';
import '../widgets/auth_card.dart';
import '../widgets/auth_form_fields.dart';
import '../widgets/auth_page_scaffold.dart';
import '../widgets/auth_submit_button.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    required this.authService,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final AuthNavigator navigator;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  EmailVerificationController? _controller;
  final TextEditingController _code = TextEditingController();

  EmailVerificationController get controller => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final arguments =
        ModalRoute.of(context)?.settings.arguments
            as VerificationPageArguments?;
    if (arguments == null) return;
    _controller = EmailVerificationController(
      widget.authService,
      mode: arguments.mode,
      challenge: arguments.challenge,
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await controller.submit();
    if (!mounted) return;
    if (outcome != EmailVerificationOutcome.verified) return;
    switch (controller.mode) {
      case EmailVerificationMode.registration:
        widget.navigator.goToHome();
      case EmailVerificationMode.emailChange:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('邮箱已更新')));
        widget.navigator.goToProfile();
    }
  }

  Future<void> _resend() async {
    await controller.resend();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '邮箱验证',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final isRegistration =
              controller.mode == EmailVerificationMode.registration;
          final resendSeconds = controller.resendSecondsRemaining;
          final resendLabel = controller.canResend
              ? '重新发送验证码'
              : resendSeconds > 0
              ? '重新发送（${resendSeconds}s）'
              : '重新发送验证码';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              const Text('验证你的邮箱', style: AuthDesignTokens.pageTitleStyle),
              const SizedBox(height: 8),
              Text(
                '验证码已发送至 ${controller.maskedEmail}',
                style: AuthDesignTokens.hintTextStyle,
              ),
              const SizedBox(height: 20),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthTextField(
                      label: '6 位验证码',
                      controller: _code,
                      errorText: controller.codeError,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onChanged: controller.setCode,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (controller.formError != null) ...[
                      const SizedBox(height: 12),
                      AuthFormErrorBanner(message: controller.formError!),
                    ],
                    if (controller.resendError != null) ...[
                      const SizedBox(height: 12),
                      AuthFormErrorBanner(message: controller.resendError!),
                    ],
                    const SizedBox(height: 20),
                    AuthSubmitButton(
                      label: '确认验证',
                      loading: controller.isSubmitting,
                      onPressed: _submit,
                    ),
                    // emailChange 模式契约没有 resend 端点：隐藏入口而非伪死按钮。
                    if (isRegistration) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: controller.canResend ? _resend : null,
                          child: Text(
                            resendLabel,
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
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: controller.isSubmitting
                      ? null
                      : isRegistration
                      ? () => widget.navigator.goToLogin()
                      : () => widget.navigator.goToProfile(),
                  child: Text(
                    isRegistration ? '返回登录' : '返回个人信息',
                    style: const TextStyle(
                      color: AuthDesignTokens.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

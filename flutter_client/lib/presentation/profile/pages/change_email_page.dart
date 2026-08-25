import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../app/routing/auth_route_arguments.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/email_verification_controller.dart';
import '../../../application/user/change_email_controller.dart';
import '../../../native_contract/user/current_user_response_dto.dart';
import '../../auth/auth_design_tokens.dart';
import '../../auth/widgets/auth_card.dart';
import '../../auth/widgets/auth_form_fields.dart';
import '../../auth/widgets/auth_page_scaffold.dart';
import '../../auth/widgets/auth_submit_button.dart';

class ChangeEmailPage extends StatefulWidget {
  const ChangeEmailPage({
    required this.authService,
    required this.initialUser,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final CurrentUserResponseDto initialUser;
  final AuthNavigator navigator;

  @override
  State<ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<ChangeEmailPage> {
  late final ChangeEmailController _controller;
  final TextEditingController _newEmail = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = ChangeEmailController(
      widget.authService,
      initialUser: widget.initialUser,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _newEmail.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (!mounted) return;
    final challenge = _controller.challenge;
    if (outcome == ChangeEmailOutcome.requested && challenge != null) {
      widget.navigator.goToVerification(
        VerificationPageArguments(
          challenge: challenge,
          mode: EmailVerificationMode.emailChange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '修改邮箱',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                '新邮箱验证完成前，登录邮箱不会改变',
                style: AuthDesignTokens.hintTextStyle,
              ),
              const SizedBox(height: 16),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('当前邮箱', style: AuthDesignTokens.fieldLabelStyle),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _controller.currentEmail,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AuthDesignTokens.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '新邮箱',
                      controller: _newEmail,
                      errorText: _controller.newEmailError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setNewEmail,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '当前密码',
                      controller: _password,
                      errorText: _controller.currentPasswordError,
                      obscureText: _controller.obscurePassword,
                      textInputAction: TextInputAction.done,
                      onChanged: _controller.setCurrentPassword,
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
                      label: '发送验证邮件',
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

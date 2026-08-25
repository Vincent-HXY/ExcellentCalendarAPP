import 'package:flutter/material.dart';

import '../../../application/auth/auth_service.dart';
import '../../../application/user/edit_profile_controller.dart';
import '../../../native_contract/user/current_user_response_dto.dart';
import '../../auth/auth_design_tokens.dart';
import '../../auth/widgets/auth_card.dart';
import '../../auth/widgets/auth_form_fields.dart';
import '../../auth/widgets/auth_page_scaffold.dart';
import '../../auth/widgets/auth_submit_button.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({
    required this.authService,
    required this.initialUser,
    super.key,
  });

  final AuthService authService;
  final CurrentUserResponseDto initialUser;

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late final EditProfileController _controller;
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _locale = TextEditingController();
  final TextEditingController _timezone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = EditProfileController(
      widget.authService,
      initialUser: widget.initialUser,
    );
    _displayName.text = _controller.displayName;
    _username.text = _controller.username;
    _locale.text = _controller.locale;
    _timezone.text = _controller.timezone;
  }

  @override
  void dispose() {
    _controller.dispose();
    _displayName.dispose();
    _username.dispose();
    _locale.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final outcome = await _controller.submit();
    if (!mounted) return;
    if (outcome == EditProfileOutcome.saved) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('资料已保存')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '编辑资料',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                '登录邮箱与密码需在“账号安全”中修改',
                style: AuthDesignTokens.hintTextStyle,
              ),
              const SizedBox(height: 16),
              AuthCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AuthTextField(
                      label: '昵称',
                      controller: _displayName,
                      errorText: _controller.displayNameError,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setDisplayName,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '用户名',
                      controller: _username,
                      errorText: _controller.usernameError,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setUsername,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '语言（如 zh-CN）',
                      controller: _locale,
                      errorText: _controller.localeError,
                      textInputAction: TextInputAction.next,
                      onChanged: _controller.setLocale,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      label: '时区（如 Asia/Shanghai）',
                      controller: _timezone,
                      errorText: _controller.timezoneError,
                      textInputAction: TextInputAction.done,
                      onChanged: _controller.setTimezone,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_controller.formError != null) ...[
                      const SizedBox(height: 14),
                      AuthFormErrorBanner(message: _controller.formError!),
                    ],
                    const SizedBox(height: 20),
                    AuthSubmitButton(
                      label: '保存',
                      loading: _controller.isSubmitting,
                      onPressed: _controller.canSave ? _submit : null,
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

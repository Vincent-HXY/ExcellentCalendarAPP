import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../email_verification/email_verification_page.dart';

/// Register page — email, username, display name, password, confirm password.
///
/// States: initial, inputting, submitting, validationError, serverError, success.
class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.authController, super.key});

  final AuthController authController;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      setState(() => _errorMessage = '请同意用户协议');
      return;
    }
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.register(
        email: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        displayName: _displayNameController.text.trim(),
        password: _passwordController.text,
      );

      if (_disposed) return;

      if (success) {
        setState(() => _isSubmitting = false);

        if (!_disposed) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmailVerificationPage(
                authController: widget.authController,
                email: _emailController.text.trim(),
              ),
            ),
          );
        }
      } else {
        final error = widget.authController.state.errorMessage;
        setState(() {
          _isSubmitting = false;
          _errorMessage = error ?? '注册失败，请重试';
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = '网络错误，请检查网络连接后重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF111827)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '创建账号',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '注册后请验证你的邮箱',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 28),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 20, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                  fontSize: 14, color: Color(0xFFDC2626)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _buildTextField(_emailController, '邮箱', '请输入邮箱',
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入邮箱';
                    if (!v.contains('@')) return '邮箱格式不正确';
                    return null;
                  }),
                  const SizedBox(height: 14),

                  _buildTextField(_usernameController, '用户名', '字母数字组合，3-50个字符',
                      validator: (v) {
                    if (v == null || v.trim().length < 3) return '用户名至少3个字符';
                    if (v.trim().length > 50) return '用户名不能超过50个字符';
                    return null;
                  }),
                  const SizedBox(height: 14),

                  _buildTextField(
                      _displayNameController, '昵称', '你的显示名称',
                      validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入昵称';
                    if (v.trim().length > 100) return '昵称不能超过100个字符';
                    return null;
                  }),
                  const SizedBox(height: 14),

                  _buildTextField(_passwordController, '密码', '至少8个字符',
                      obscureText: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: const Color(0xFF6B7280),
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) {
                    if (v == null || v.length < 8) return '密码至少8个字符';
                    return null;
                  }),
                  const SizedBox(height: 14),

                  _buildTextField(_confirmPasswordController, '确认密码', '再次输入密码',
                      obscureText: _obscureConfirm,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: const Color(0xFF6B7280),
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      validator: (v) {
                    if (v != _passwordController.text) return '两次密码不一致';
                    return null;
                  }),
                  const SizedBox(height: 16),

                  // Terms agreement
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: _agreedToTerms,
                          onChanged: (v) =>
                              setState(() => _agreedToTerms = v ?? false),
                          activeColor: const Color(0xFF38B9C5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _agreedToTerms = !_agreedToTerms),
                          child: const Text(
                            '我已阅读并同意用户协议',
                            style: TextStyle(
                                fontSize: 14, color: Color(0xFF374151)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Register button
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _handleRegister,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF38B9C5),
                        disabledBackgroundColor: const Color(0xFF9CA3AF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text(
                              '注册',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Login link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '已有账号？',
                        style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text(
                          '登录',
                          style: TextStyle(
                            color: Color(0xFF38B9C5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscureText = false,
    Widget? suffix,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: suffix,
      ),
      validator: validator,
    );
  }
}
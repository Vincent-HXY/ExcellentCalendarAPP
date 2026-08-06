import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../email_verification/email_verification_page.dart';
import '../forgot_password/forgot_password_page.dart';
import '../register/register_page.dart';

/// Login page — email + password form.
///
/// States: initial, inputting, submitting, success, error, networkError.
class LoginPage extends StatefulWidget {
  const LoginPage({
    required this.authController,
    super.key,
  });

  final AuthController authController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChange);
  }

  @override
  void dispose() {
    _disposed = true;
    widget.authController.removeListener(_onAuthChange);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onAuthChange() {
    if (_disposed) return;
    final state = widget.authController.state;
    if (state.isAuthenticated) {
      Navigator.of(context).pushReplacementNamed('/today');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (_disposed) return;

      if (success) {
        // AuthController will notify and navigate via _onAuthChange
      } else {
        final error = widget.authController.state.errorMessage;
        if (error?.contains('unverified') == true ||
            error?.contains('EMAIL_UNVERIFIED') == true) {
          _navigateToEmailVerification();
          return;
        }
        setState(() {
          _isSubmitting = false;
          _errorMessage = _translateError(error);
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

  String _translateError(String? error) {
    if (error == null) return '登录失败，请重试';
    if (error.contains('INVALID_CREDENTIALS') || error.contains('incorrect')) {
      return '邮箱或密码错误';
    }
    if (error.contains('DISABLED')) {
      return '账号已被禁用';
    }
    if (error.contains('RATE_LIMITED')) {
      return '请求过于频繁，请稍后重试';
    }
    return '登录失败，请重试';
  }

  void _navigateToEmailVerification() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmailVerificationPage(
          authController: widget.authController,
          email: _emailController.text.trim(),
        ),
      ),
    );
  }

  void _navigateToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterPage(authController: widget.authController),
      ),
    );
  }

  void _navigateToForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(authController: widget.authController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
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
                  // Logo
                  const Icon(
                    Icons.event_note_rounded,
                    size: 56,
                    color: Color(0xFF38B9C5),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Excellent Calendar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '登录你的账号',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 32),

                  // Error banner
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

                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: _inputDecoration('邮箱', '请输入邮箱'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入邮箱';
                      if (!v.contains('@')) return '邮箱格式不正确';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    decoration: _inputDecoration('密码', '请输入密码').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: const Color(0xFF6B7280),
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请输入密码';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _navigateToForgotPassword,
                      child: const Text(
                        '忘记密码？',
                        style: TextStyle(
                          color: Color(0xFF38B9C5),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Login button
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _handleLogin,
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
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '登录',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '还没有账号？',
                        style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                      ),
                      TextButton(
                        onPressed: _navigateToRegister,
                        child: const Text(
                          '注册',
                          style: TextStyle(
                            color: Color(0xFF38B9C5),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}
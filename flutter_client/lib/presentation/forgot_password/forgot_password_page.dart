import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../reset_password/reset_password_page.dart';

/// Forgot password page — enter email to receive reset code.
///
/// States: initial, inputting, submitting, success, error, resendCooldown.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({required this.authController, super.key});

  final AuthController authController;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isResending = false;
  bool _emailSent = false;
  String? _errorMessage;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _emailController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _countdown = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleSend() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.forgotPassword(
        email: _emailController.text.trim(),
      );
      if (_disposed) return;

      setState(() {
        _isSubmitting = false;
        _emailSent = success;
      });
      if (success) {
        _startCountdown();
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

  Future<void> _handleResend() async {
    if (_isResending || _countdown > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.forgotPassword(
        email: _emailController.text.trim(),
      );
      if (_disposed) return;

      if (success) {
        setState(() => _isResending = false);
        _startCountdown();
      } else {
        setState(() {
          _isResending = false;
          _errorMessage = '发送失败，请重试';
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _isResending = false;
          _errorMessage = '发送失败，请重试';
        });
      }
    }
  }

  void _navigateToResetPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordPage(
          authController: widget.authController,
          email: _emailController.text.trim(),
        ),
      ),
    );
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
                  const Icon(Icons.lock_reset_rounded,
                      size: 56, color: Color(0xFF38B9C5)),
                  const SizedBox(height: 16),
                  const Text(
                    '忘记密码',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '输入你的注册邮箱，我们将发送重置密码的验证码',
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

                  if (_emailSent) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 20, color: Color(0xFF059669)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '如果该邮箱已经注册，系统会向该邮箱发送密码重置邮件。请检查收件箱和垃圾邮件。',
                              style: TextStyle(
                                  fontSize: 14, color: Color(0xFF065F46)),
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
                    decoration: InputDecoration(
                      labelText: '邮箱',
                      hintText: '请输入注册邮箱',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '请输入邮箱';
                      if (!v.contains('@')) return '邮箱格式不正确';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Send button
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _handleSend,
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
                          : const Text('发送重置邮件',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                  ),

                  if (_emailSent) ...[
                    const SizedBox(height: 16),
                    // Resend
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          '没有收到邮件？',
                          style: TextStyle(
                              fontSize: 14, color: Color(0xFF6B7280)),
                        ),
                        TextButton(
                          onPressed: (_countdown > 0 || _isResending)
                              ? null
                              : _handleResend,
                          child: _isResending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF38B9C5)),
                                )
                              : Text(
                                  _countdown > 0
                                      ? '重新发送($_countdown)'
                                      : '重新发送',
                                  style: TextStyle(
                                    color: _countdown > 0
                                        ? const Color(0xFF9CA3AF)
                                        : const Color(0xFF38B9C5),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _navigateToResetPassword,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('已收到验证码，去重置密码',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';

/// Email verification page — enter 6-digit code, resend with countdown.
///
/// States: initial, inputting, submitting, success, error, resendCooldown.
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    required this.authController,
    required this.email,
    this.isEmailChange = false,
    super.key,
  });

  final AuthController authController;
  final String email;
  final bool isEmailChange;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _isResending = false;
  String? _errorMessage;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _disposed = false;

  String get _maskedEmail {
    final parts = widget.email.split('@');
    if (parts.length != 2) return widget.email;
    final name = parts[0];
    if (name.length <= 2) return '${name[0]}***@${parts[1]}';
    return '${name[0]}${name[1]}***@${parts[1]}';
  }

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _disposed = true;
    _codeController.dispose();
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

  Future<void> _handleVerify() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.verifyEmail(
        code: _codeController.text.trim(),
      );

      if (_disposed) return;

      if (success) {
        setState(() => _isSubmitting = false);
        if (!_disposed) {
          Navigator.of(context).pushNamedAndRemoveUntil('/today', (_) => false);
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = '验证码无效或已过期，请重试';
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

  Future<void> _handleResend() async {
    if (_isResending || _countdown > 0) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.resendVerificationCode();
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
                  const Icon(Icons.mark_email_unread_rounded,
                      size: 56, color: Color(0xFF38B9C5)),
                  const SizedBox(height: 16),
                  Text(
                    widget.isEmailChange ? '验证新邮箱' : '验证邮箱',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '验证码已发送至 $_maskedEmail',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
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

                  // Code input
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: '000000',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18),
                    ),
                    style: const TextStyle(
                        fontSize: 28,
                        letterSpacing: 12,
                        fontWeight: FontWeight.w600),
                    validator: (v) {
                      if (v == null || v.length != 6) return '请输入6位验证码';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Verify button
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _handleVerify,
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
                          : const Text('验证',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Resend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '没有收到验证码？',
                        style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed:
                            (_countdown > 0 || _isResending) ? null : _handleResend,
                        child: _isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF38B9C5)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../email_verification/email_verification_page.dart';

/// Change email page — enter new email, current password, then verify.
class ProfileEmailPage extends StatefulWidget {
  const ProfileEmailPage({
    required this.authController,
    required this.currentEmail,
    required this.emailVerified,
    super.key,
  });

  final AuthController authController;
  final String currentEmail;
  final bool emailVerified;

  @override
  State<ProfileEmailPage> createState() => _ProfileEmailPageState();
}

class _ProfileEmailPageState extends State<ProfileEmailPage> {
  final _newEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _newEmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestChange() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.authController.changeEmail(
        newEmail: _newEmailController.text.trim(),
        currentPassword: _passwordController.text,
      );
      if (_disposed) return;

      if (success) {
        setState(() => _isSubmitting = false);

        // Navigate to email verification page
        if (!_disposed) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmailVerificationPage(
                authController: widget.authController,
                email: _newEmailController.text.trim(),
                isEmailChange: true,
              ),
            ),
          );
        }
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = '修改邮箱失败，请重试';
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
        title: const Text(
          '修改邮箱',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Current email (read-only)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('当前邮箱',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF6B7280))),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            widget.currentEmail,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.emailVerified
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.emailVerified ? '已验证' : '未验证',
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.emailVerified
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // New email form
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: '新邮箱',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '请输入新邮箱';
                          if (!v.contains('@')) return '邮箱格式不正确';
                          if (v.trim() == widget.currentEmail) {
                            return '新邮箱不能与当前邮箱相同';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: '当前密码',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: const Color(0xFF6B7280),
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '请输入当前密码';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

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
                          child: Text(_errorMessage!,
                              style: const TextStyle(
                                  fontSize: 14, color: Color(0xFFDC2626))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _handleRequestChange,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38B9C5),
                      disabledBackgroundColor: const Color(0xFF9CA3AF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('发送验证邮件',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
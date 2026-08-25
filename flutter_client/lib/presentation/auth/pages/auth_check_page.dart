import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../application/auth/startup_auth_check_use_case.dart';
import '../auth_design_tokens.dart';

enum _AuthCheckPhase { checking, failed }

/// Startup gate: restores the session or routes to login/recovery.
class AuthCheckPage extends StatefulWidget {
  const AuthCheckPage({
    required this.startupCheck,
    required this.navigator,
    super.key,
  });

  final StartupAuthCheckUseCase startupCheck;
  final AuthNavigator navigator;

  @override
  State<AuthCheckPage> createState() => _AuthCheckPageState();
}

class _AuthCheckPageState extends State<AuthCheckPage> {
  _AuthCheckPhase _phase = _AuthCheckPhase.checking;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _phase = _AuthCheckPhase.checking);
    final result = await widget.startupCheck.run();
    if (!mounted) return;
    switch (result) {
      case StartupAuthResult.authenticated:
        widget.navigator.goToHome();
      case StartupAuthResult.unauthenticated:
        widget.navigator.goToLogin();
      case StartupAuthResult.recoveryFailed:
        setState(() => _phase = _AuthCheckPhase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthDesignTokens.pageBackground,
      body: SafeArea(
        child: Center(
          child: _phase == _AuthCheckPhase.checking
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AuthDesignTokens.primary),
                    SizedBox(height: 16),
                    Text(
                      '正在恢复登录状态…',
                      style: TextStyle(
                        fontSize: 14,
                        color: AuthDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                )
              : Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 44,
                        color: AuthDesignTokens.textMuted,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '登录状态恢复失败',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AuthDesignTokens.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '当前网络不可用，请检查网络连接后重试',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AuthDesignTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _run,
                        style: FilledButton.styleFrom(
                          backgroundColor: AuthDesignTokens.primary,
                        ),
                        child: const Text('重试'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: widget.navigator.goToLogin,
                        child: const Text(
                          '改用其他账号登录',
                          style: TextStyle(color: AuthDesignTokens.primary),
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

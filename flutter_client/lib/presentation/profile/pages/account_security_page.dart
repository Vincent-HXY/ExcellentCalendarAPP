import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../application/auth/logout_service.dart';
import '../../../application/user/account_security_controller.dart';
import '../../auth/auth_design_tokens.dart';
import '../../auth/widgets/auth_page_scaffold.dart';

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({
    required this.logoutService,
    required this.navigator,
    super.key,
  });

  final LogoutService logoutService;
  final AuthNavigator navigator;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  late final AccountSecurityController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AccountSecurityController(widget.logoutService);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await _confirm('退出登录', '确定要退出当前设备吗？');
    if (confirmed != true || !mounted) return;
    final outcome = await _controller.logout();
    if (!mounted) return;
    if (outcome == AccountSecurityOutcome.failed &&
        _controller.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_controller.errorMessage!)));
    }
    widget.navigator.goToLogin();
  }

  Future<void> _logoutAll() async {
    final confirmed = await _confirm('退出所有设备', '确定要退出所有已登录设备吗？');
    if (confirmed != true || !mounted) return;
    final outcome = await _controller.logoutAll();
    if (!mounted) return;
    if (outcome == AccountSecurityOutcome.failed &&
        _controller.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_controller.errorMessage!)));
    }
    widget.navigator.goToLogin();
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '账号安全',
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final working = _controller.isWorking;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _SecurityTile(
                icon: Icons.lock_outline_rounded,
                label: '修改密码',
                onTap: working
                    ? null
                    : () => widget.navigator.push('/profile/password'),
              ),
              const SizedBox(height: 10),
              _SecurityTile(
                icon: Icons.alternate_email_rounded,
                label: '修改登录邮箱',
                onTap: working
                    ? null
                    : () => widget.navigator.push('/profile/email'),
              ),
              const SizedBox(height: 10),
              _SecurityTile(
                icon: Icons.logout_rounded,
                label: '退出当前设备',
                onTap: working ? null : _logout,
              ),
              const SizedBox(height: 10),
              _SecurityTile(
                icon: Icons.devices_other_rounded,
                label: '退出所有设备',
                onTap: working ? null : _logoutAll,
                destructive: true,
              ),
              if (working) ...[
                const SizedBox(height: 18),
                const Center(
                  child: CircularProgressIndicator(
                    color: AuthDesignTokens.primary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AuthDesignTokens.error
        : AuthDesignTokens.textSecondary;
    return Material(
      color: AuthDesignTokens.cardBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: color),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AuthDesignTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

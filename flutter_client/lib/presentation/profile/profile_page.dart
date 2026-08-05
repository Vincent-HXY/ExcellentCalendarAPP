import 'package:flutter/material.dart';

import '../../auth/auth_api_client.dart';
import '../../auth/auth_controller.dart';
import '../profile_avatar/profile_avatar_page.dart';
import '../profile_edit/profile_edit_page.dart';
import '../profile_email/profile_email_page.dart';
import '../profile_password/profile_password_page.dart';

/// Profile page — shows user info and links to edit pages.
///
/// Loads from cache first, then fetches latest from server.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.authController,
    super.key,
  });

  final AuthController authController;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Simulated profile data — will be replaced with real API calls
  String _displayName = 'User';
  String _username = 'user';
  String _email = 'user@example.com';
  bool _emailVerified = false;
  String? _avatarUrl;
  bool _isLoading = false;
  bool _hasCache = false;
  String? _errorMessage;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await widget.authController.getProfile();
      if (_disposed) return;

      if (profile != null) {
        setState(() {
          _isLoading = false;
          _hasCache = true;
          _displayName = profile.displayName;
          _username = profile.username;
          _email = profile.email;
          _emailVerified = profile.emailVerified;
          _avatarUrl = profile.avatarUrl;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          if (!_hasCache) {
            _errorMessage = '加载失败，请重试';
          }
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _isLoading = false;
          if (!_hasCache) {
            _errorMessage = '加载失败，请重试';
          }
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.authController.logout();
      if (!_disposed) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }

  Future<void> _logoutAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出所有设备'),
        content: const Text('这将使所有设备上的登录会话失效，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出所有设备',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.authController.logoutAll();
      if (!_disposed) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
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
        title: const Text(
          '个人信息',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null && !_hasCache) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Color(0xFFEF4444)),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF374151))),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF38B9C5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Avatar
          Center(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileAvatarPage(
                      authController: widget.authController,
                      currentAvatarUrl: _avatarUrl,
                    ),
                  ),
                );
              },
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF38B9C5),
                    backgroundImage:
                        _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                    child: _avatarUrl == null
                        ? Text(
                            _displayName.isNotEmpty
                                ? _displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 36, color: Colors.white),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF38B9C5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (_isLoading && _hasCache)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  '信息可能不是最新',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ),
            ),
          if (_errorMessage != null && _hasCache)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: GestureDetector(
                  onTap: _loadProfile,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, size: 14, color: Color(0xFF38B9C5)),
                      SizedBox(width: 4),
                      Text(
                        '加载失败，点击重试',
                        style: TextStyle(fontSize: 12, color: Color(0xFF38B9C5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Info cards
          _buildInfoCard([
            _infoRow('昵称', _displayName),
            _infoRow('用户名', _username),
            _infoRow('邮箱', _email),
            _buildEmailVerifiedRow(),
          ]),
          const SizedBox(height: 16),

          // Menu items
          _buildMenuItem(
            icon: Icons.edit_rounded,
            title: '编辑资料',
            onTap: () async {
              final result = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => ProfileEditPage(
                    authController: widget.authController,
                    currentDisplayName: _displayName,
                    currentUsername: _username,
                  ),
                ),
              );
              if (result != null) {
                setState(() => _displayName = result);
              }
            },
          ),
          _buildMenuItem(
            icon: Icons.lock_rounded,
            title: '修改密码',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePasswordPage(
                    authController: widget.authController,
                  ),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.email_rounded,
            title: '修改邮箱',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileEmailPage(
                    authController: widget.authController,
                    currentEmail: _email,
                    emailVerified: _emailVerified,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          // Logout
          _buildMenuItem(
            icon: Icons.logout_rounded,
            title: '退出登录',
            textColor: const Color(0xFFEF4444),
            onTap: _logout,
          ),
          _buildMenuItem(
            icon: Icons.devices_rounded,
            title: '退出所有设备',
            textColor: const Color(0xFFEF4444),
            onTap: _logoutAll,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: children),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827))),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailVerifiedRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 72,
            child: Text('邮箱状态',
                style: TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _emailVerified
                  ? const Color(0xFFD1FAE5)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _emailVerified ? '已验证' : '未验证',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _emailVerified
                    ? const Color(0xFF059669)
                    : const Color(0xFFD97706),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: textColor ?? const Color(0xFF38B9C5)),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: textColor ?? const Color(0xFF111827),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Color(0xFF9CA3AF)),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
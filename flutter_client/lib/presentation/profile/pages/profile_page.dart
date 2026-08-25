import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/routing/auth_navigator.dart';
import '../../../application/auth/auth_service.dart';
import '../../../application/auth/auth_session_controller.dart';
import '../../../application/user/profile_controller.dart';
import '../widgets/profile_info_row.dart';
import '../../auth/auth_design_tokens.dart';
import '../../auth/widgets/auth_page_scaffold.dart';

/// Profile page depends only on the Application layer and routing; contract
/// DTOs and the data cache never appear in this file's own source.
class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.authService,
    required this.session,
    required this.navigator,
    super.key,
  });

  final AuthService authService;
  final AuthSessionController session;
  final AuthNavigator navigator;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileController _controller;

  ProfileController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProfileController(
      authService: widget.authService,
      session: widget.session,
      profileCache: widget.authService.profileCache,
    );
    controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteAvatar() async {
    final oldThumbnailUrl = controller.viewData?.avatarThumbnailUrl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除头像'),
        content: const Text('确定要删除当前头像吗？删除后将恢复默认头像。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final outcome = await controller.deleteAvatar();
    if (!mounted) return;
    if (outcome == ProfileActionOutcome.failed &&
        controller.actionError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.actionError!)));
      return;
    }
    if (outcome == ProfileActionOutcome.deletedAvatar &&
        oldThumbnailUrl != null) {
      // 服务端已删除：清掉内存 ImageCache 中的旧头像，避免残留占用。
      unawaited(NetworkImage(oldThumbnailUrl).evict());
    }
  }

  void _showAvatarChangeUnsupported() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('头像修改功能暂不支持')));
  }

  @override
  Widget build(BuildContext context) {
    return AuthPageScaffold(
      title: '个人信息',
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final viewData = controller.viewData;
          if (controller.phase == ProfileLoadPhase.loading &&
              viewData == null) {
            return const Padding(
              padding: EdgeInsets.only(top: 96),
              child: Center(
                child: CircularProgressIndicator(
                  color: AuthDesignTokens.primary,
                ),
              ),
            );
          }
          if (viewData == null) {
            return _ProfileErrorState(
              message: controller.errorMessage ?? '加载失败',
              onRetry: controller.load,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              if (controller.phase == ProfileLoadPhase.stale)
                _StaleBanner(onReload: controller.load),
              const SizedBox(height: 12),
              Center(
                child: _Avatar(
                  viewData: viewData,
                  isDeleting: controller.isDeletingAvatar,
                  onChange: _showAvatarChangeUnsupported,
                  onDelete: viewData.hasAvatar ? _confirmDeleteAvatar : null,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AuthDesignTokens.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ProfileInfoRow(label: '昵称', value: viewData.displayName),
                    ProfileInfoRow(label: '用户名', value: viewData.username),
                    ProfileInfoRow(label: '登录邮箱', value: viewData.email),
                    ProfileInfoRow(
                      label: '邮箱验证',
                      value: viewData.isEmailVerified ? '已验证' : '未验证',
                    ),
                    ProfileInfoRow(label: '语言', value: viewData.locale),
                    ProfileInfoRow(label: '时区', value: viewData.timezone),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _ProfileActionTile(
                icon: Icons.edit_outlined,
                label: '编辑资料',
                onTap: () => widget.navigator.push('/profile/edit'),
              ),
              const SizedBox(height: 10),
              _ProfileActionTile(
                icon: Icons.shield_outlined,
                label: '账号安全',
                onTap: () => widget.navigator.push('/account-security'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xFFB45309),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '信息可能不是最新',
              style: TextStyle(fontSize: 13, color: Color(0xFFB45309)),
            ),
          ),
          TextButton(onPressed: onReload, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

class _ProfileErrorState extends StatelessWidget {
  const _ProfileErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 72),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: AuthDesignTokens.textMuted,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.viewData,
    required this.isDeleting,
    required this.onChange,
    required this.onDelete,
  });

  final ProfileViewData viewData;
  final bool isDeleting;
  final VoidCallback onChange;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = viewData.avatarThumbnailUrl;
    final image = thumbnailUrl == null
        ? null
        : Image.network(
            thumbnailUrl,
            width: 88,
            height: 88,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _fallback(),
          );
    return Column(
      children: [
        ClipOval(
          child: SizedBox(
            width: 88,
            height: 88,
            child: isDeleting
                ? const ColoredBox(
                    color: Color(0xFFD1D5DB),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AuthDesignTokens.primary,
                      ),
                    ),
                  )
                : image ?? _fallback(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: isDeleting ? null : onChange,
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: const Text('更换头像'),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: isDeleting ? null : onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('删除头像'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _fallback() => const ColoredBox(
    color: Color(0xFFBDE7EC),
    child: Icon(Icons.person_rounded, size: 44, color: Color(0xFF0E7490)),
  );
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              Icon(icon, size: 20, color: AuthDesignTokens.textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AuthDesignTokens.textPrimary,
                  ),
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

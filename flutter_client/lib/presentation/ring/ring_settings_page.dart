import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/ring/ring_settings_controller.dart';
import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/ring/ring_contract_enums.dart';
import '../../native_contract/ring/ring_state_dtos.dart';
import '../app_design_tokens.dart';

class RingSettingsPage extends StatefulWidget {
  const RingSettingsPage({required this.gateway, super.key});

  final RingNativeGateway gateway;

  @override
  State<RingSettingsPage> createState() => _RingSettingsPageState();
}

class _RingSettingsPageState extends State<RingSettingsPage> {
  late final RingSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RingSettingsController(gateway: widget.gateway);
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.brightness == Brightness.light
        ? AppColors.lightPageBackground
        : theme.colorScheme.surface;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        title: const Text('响铃设置'),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, child) => _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final snapshot = _controller.snapshot;
    if (snapshot == null &&
        _controller.status == RingSettingsLoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return _StatusPanel(
        message: _controller.errorMessage ?? '无法读取响铃设置',
        onRetry: _controller.refresh,
      );
    }
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Row(
              children: [
                const _SettingIcon(
                  icon: Icons.notifications_active_outlined,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '听见每一份重要',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '选择喜欢的铃声，按你的方式提醒',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_controller.errorMessage case final message?)
            _MessageCard(message: message, isError: true),
          if (_controller.notice case final message?)
            _MessageCard(message: message),
          const _SectionLabel(title: '提醒偏好'),
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  leading: const _SettingIcon(icon: Icons.music_note_rounded),
                  title: const Text('铃声'),
                  subtitle: Text(
                    snapshot.settings.ringtoneAvailable
                        ? snapshot.settings.ringtoneDisplayName
                        : '${snapshot.settings.ringtoneDisplayName}（不可用，将使用系统默认铃声）',
                  ),
                  subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    height: 1.5,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_controller.isBusy,
                  onTap: _controller.isBusy ? null : _controller.pickRingtone,
                ),
                Divider(
                  height: 1,
                  indent: 18,
                  endIndent: 18,
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  title: const Text('强提醒'),
                  subtitle: Text(
                    '平台允许时请求全屏显示；不可用时仍会正常响铃',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  value: snapshot.settings.strongReminderEnabled,
                  onChanged: _controller.isBusy
                      ? null
                      : _controller.setStrongReminderEnabled,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: Icon(
              snapshot.testState == RingTestState.audible
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
            ),
            label: Text(
              snapshot.testState == RingTestState.audible ? '停止测试' : '测试响铃',
            ),
            onPressed: _controller.isBusy || snapshot.activeSession != null
                ? null
                : _controller.toggleTest,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            child: Text(
              snapshot.activeSession == null
                  ? '仅测试声音与振动，不创建提醒记录'
                  : '活动响铃期间不能测试',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const _SectionLabel(title: '设备状态', subtitle: '下拉刷新，查看最新权限状态'),
          _CapabilityCard(capability: snapshot.capability),
          if (_controller.isBusy) ...[
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                label: '正在处理响铃设置',
                child: const CircularProgressIndicator(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.capability});

  final RingCapabilitySnapshotDto capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  capability.canEnableRing
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: capability.canEnableRing
                      ? colors.primary
                      : colors.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    capability.canEnableRing ? '响铃能力可用' : '响铃能力受限',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            _CapabilityRow(
              icon: Icons.notifications_none_rounded,
              label: '通知权限',
              value: _notificationLabel(capability.notificationPermission),
            ),
            _CapabilityRow(
              icon: Icons.alarm_rounded,
              label: '精确闹钟',
              value: _exactAlarmLabel(capability.exactAlarmPermission),
            ),
            _CapabilityRow(
              icon: Icons.fullscreen_rounded,
              label: '全屏提醒',
              value: _fullScreenLabel(capability.fullScreenIntentPermission),
            ),
            _CapabilityRow(
              icon: Icons.volume_up_outlined,
              label: '响铃渠道',
              value: capability.ringChannelEnabled ? '可用' : '不可用',
            ),
            if (capability.blockingReasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '需要处理：${capability.blockingReasons.map(_blockingLabel).join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.error,
                  height: 1.6,
                ),
              ),
            ],
            if (capability.degradationReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '降级状态：${capability.degradationReasons.map(_degradationLabel).join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _notificationLabel(NotificationPermissionStatus status) =>
      switch (status) {
        NotificationPermissionStatus.granted => '已允许',
        NotificationPermissionStatus.denied => '未允许',
        NotificationPermissionStatus.notRequired => '系统无需授权',
        NotificationPermissionStatus.permanentlyDenied => '已永久拒绝',
        NotificationPermissionStatus.unknown => '未知',
      };

  static String _exactAlarmLabel(ExactAlarmPermissionStatus status) =>
      switch (status) {
        ExactAlarmPermissionStatus.granted => '已允许',
        ExactAlarmPermissionStatus.denied => '未允许',
        ExactAlarmPermissionStatus.notRequired => '系统无需授权',
        ExactAlarmPermissionStatus.unknown => '未知',
      };

  static String _fullScreenLabel(FullScreenIntentPermissionStatus status) =>
      switch (status) {
        FullScreenIntentPermissionStatus.granted => '已允许',
        FullScreenIntentPermissionStatus.denied => '未允许（将降级显示）',
        FullScreenIntentPermissionStatus.notRequired => '系统无需授权',
        FullScreenIntentPermissionStatus.unknown => '未知',
      };

  static String _blockingLabel(
    RingCapabilityBlockingReason reason,
  ) => switch (reason) {
    RingCapabilityBlockingReason.notificationPermissionUnavailable => '通知权限',
    RingCapabilityBlockingReason.exactAlarmPermissionUnavailable => '精确闹钟权限',
    RingCapabilityBlockingReason.ringChannelUnavailable => '响铃通知渠道',
    RingCapabilityBlockingReason.noOutputAvailable => '声音或振动输出',
  };

  static String _degradationLabel(RingCapabilityDegradationReason reason) =>
      switch (reason) {
        RingCapabilityDegradationReason.fullScreenIntentUnavailable => '无法全屏显示',
        RingCapabilityDegradationReason.selectedRingtoneUnavailable =>
          '所选铃声不可用',
        RingCapabilityDegradationReason.audioOutputUnavailable => '声音不可用',
        RingCapabilityDegradationReason.vibrationUnavailable => '振动不可用',
      };
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isError
                ? colors.onErrorContainer
                : colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SettingIcon(
              icon: Icons.notifications_off_outlined,
              size: 56,
            ),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _SettingIcon extends StatelessWidget {
  const _SettingIcon({required this.icon, this.size = 42});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: colors.primary),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

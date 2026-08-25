import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/ring/ring_settings_controller.dart';
import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/ring/ring_contract_enums.dart';
import '../../native_contract/ring/ring_state_dtos.dart';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF1FAFB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1FAFB),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_controller.errorMessage case final message?)
            _MessageCard(message: message, isError: true),
          if (_controller.notice case final message?)
            _MessageCard(message: message),
          _SettingsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: const Text('铃声'),
                  subtitle: Text(
                    snapshot.settings.ringtoneAvailable
                        ? snapshot.settings.ringtoneDisplayName
                        : '${snapshot.settings.ringtoneDisplayName}（不可用，将使用系统默认铃声）',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  enabled: !_controller.isBusy,
                  onTap: _controller.isBusy ? null : _controller.pickRingtone,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.fullscreen_rounded),
                  title: const Text('强提醒'),
                  subtitle: const Text('平台允许时请求全屏显示；不可用时仍会正常响铃'),
                  value: snapshot.settings.strongReminderEnabled,
                  onChanged: _controller.isBusy
                      ? null
                      : _controller.setStrongReminderEnabled,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.volume_up_rounded),
                  title: Text(
                    snapshot.testState == RingTestState.audible
                        ? '停止测试'
                        : '测试响铃',
                  ),
                  subtitle: snapshot.activeSession == null
                      ? const Text('仅测试声音与振动，不创建提醒记录')
                      : const Text('活动响铃期间不能测试'),
                  enabled:
                      !_controller.isBusy && snapshot.activeSession == null,
                  onTap: _controller.isBusy || snapshot.activeSession != null
                      ? null
                      : _controller.toggleTest,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
                      ? const Color(0xFF16856E)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    capability.canEnableRing ? '响铃能力可用' : '响铃能力受限',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CapabilityRow(
              label: '通知权限',
              value: _notificationLabel(capability.notificationPermission),
            ),
            _CapabilityRow(
              label: '精确闹钟',
              value: _exactAlarmLabel(capability.exactAlarmPermission),
            ),
            _CapabilityRow(
              label: '全屏提醒',
              value: _fullScreenLabel(capability.fullScreenIntentPermission),
            ),
            _CapabilityRow(
              label: '响铃渠道',
              value: capability.ringChannelEnabled ? '可用' : '不可用',
            ),
            if (capability.blockingReasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '需要处理：${capability.blockingReasons.map(_blockingLabel).join('、')}',
                style: const TextStyle(color: Color(0xFF9A3412)),
              ),
            ],
            if (capability.degradationReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '降级状态：${capability.degradationReasons.map(_degradationLabel).join('、')}',
                style: const TextStyle(color: Color(0xFF6B7280)),
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
  const _CapabilityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(color: Color(0xFF4B5563))),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
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
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? const Color(0xFFFFEDEA) : const Color(0xFFE8F8F5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

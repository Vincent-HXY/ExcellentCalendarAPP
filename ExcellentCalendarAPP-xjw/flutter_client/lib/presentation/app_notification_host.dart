import 'dart:async';

import 'package:flutter/material.dart';

import '../app/bootstrap/app_notification_bootstrap.dart';

class AppNotificationHost extends StatefulWidget {
  const AppNotificationHost({
    required this.bootstrap,
    required this.child,
    super.key,
  });

  final AppNotificationBootstrap bootstrap;
  final Widget child;

  @override
  State<AppNotificationHost> createState() => _AppNotificationHostState();
}

class _AppNotificationHostState extends State<AppNotificationHost>
    with WidgetsBindingObserver {
  bool _permissionDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.bootstrap.addListener(_handleBootstrapChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.bootstrap.start());
    });
  }

  @override
  void didUpdateWidget(covariant AppNotificationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bootstrap != widget.bootstrap) {
      oldWidget.bootstrap.removeListener(_handleBootstrapChanged);
      widget.bootstrap.addListener(_handleBootstrapChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.bootstrap.onAppResumed());
    }
  }

  void _handleBootstrapChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.bootstrap.state.needsPermissionExplanation &&
        !_permissionDialogVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showPermissionExplanation());
      });
    }
  }

  Future<void> _showPermissionExplanation() async {
    if (_permissionDialogVisible) return;
    _permissionDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('开启通知提醒'),
          content: const Text('允许通知和精确提醒后，日程提醒才能按时送达。你也可以稍后在系统设置中开启。'),
          actions: [
            TextButton(
              onPressed: () {
                widget.bootstrap.dismissPermissionExplanation();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('暂不'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(widget.bootstrap.requestPermissions());
              },
              child: const Text('允许'),
            ),
          ],
        );
      },
    );
    _permissionDialogVisible = false;
  }

  @override
  Widget build(BuildContext context) {
    final showSettings = widget.bootstrap.state.shouldOfferSettings;
    return Stack(
      children: [
        widget.child,
        if (showSettings)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: const Color(0xFFFDF3E7),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '通知权限未开启，提醒可能无法送达。',
                          style: TextStyle(
                            color: Color(0xFF7C4A16),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: widget.bootstrap.openNotificationSettings,
                        child: const Text('去设置'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bootstrap.removeListener(_handleBootstrapChanged);
    super.dispose();
  }
}

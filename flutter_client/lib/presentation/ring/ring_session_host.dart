import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/ring/active_ring_session_controller.dart';

class RingSessionHost extends StatefulWidget {
  const RingSessionHost({
    required this.controller,
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final ActiveRingSessionController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<RingSessionHost> createState() => _RingSessionHostState();
}

class _RingSessionHostState extends State<RingSessionHost> {
  final Set<String> _openedSessionIds = {};
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleStateChanged);
    unawaited(widget.controller.initialize());
  }

  @override
  void didUpdateWidget(RingSessionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleStateChanged);
    widget.controller.addListener(_handleStateChanged);
    unawaited(widget.controller.initialize());
  }

  void _handleStateChanged() {
    final sessionId = widget.controller.activeSession?.sessionId;
    if (sessionId == null ||
        _openedSessionIds.contains(sessionId) ||
        _navigationScheduled) {
      return;
    }
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (!mounted) return;
      final currentSessionId = widget.controller.activeSession?.sessionId;
      if (currentSessionId == null ||
          _openedSessionIds.contains(currentSessionId)) {
        return;
      }
      final navigator = widget.navigatorKey.currentState;
      if (navigator == null) return;
      _openedSessionIds.add(currentSessionId);
      unawaited(navigator.pushNamed<void>('/ring/active'));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.controller.removeListener(_handleStateChanged);
    super.dispose();
  }
}

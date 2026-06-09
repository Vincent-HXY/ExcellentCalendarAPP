import 'package:flutter/material.dart';

import '../../app_design_tokens.dart';
import '../inbox_design_tokens.dart';

class AddTaskButton extends StatefulWidget {
  const AddTaskButton({required this.onPressed, super.key});

  final Future<void> Function() onPressed;

  @override
  State<AddTaskButton> createState() => _AddTaskButtonState();
}

class _AddTaskButtonState extends State<AddTaskButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  var _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      value: 1,
      lowerBound: 0.91,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _shrink() {
    if (_isNavigating) {
      return Future.value();
    }
    return _scaleController.animateTo(
      0.91,
      duration: AppMotion.fabPress,
      curve: AppMotion.press,
    );
  }

  Future<void> _restore() {
    return _scaleController.animateTo(
      1,
      duration: AppMotion.fabRelease,
      curve: AppMotion.release,
    );
  }

  Future<void> _handleTapUp(TapUpDetails details) async {
    if (_isNavigating) {
      return;
    }
    _isNavigating = true;
    await _restore();
    await Future<void>.delayed(AppMotion.fabPostReleasePause);
    if (!mounted) {
      return;
    }
    try {
      await widget.onPressed();
    } finally {
      if (mounted) {
        _isNavigating = false;
      }
    }
  }

  void _handleTapCancel() {
    if (_isNavigating) {
      return;
    }
    _restore();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (disableAnimations && _scaleController.value != 1) {
      _scaleController.value = 1;
    }

    return Semantics(
      button: true,
      label: '新建日程',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disableAnimations ? null : (_) => _shrink(),
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: SizedBox(
          width: 58,
          height: 58,
          child: ScaleTransition(
            scale: _scaleController,
            child: Material(
              color: InboxColors.accent,
              shape: const CircleBorder(),
              elevation: 8,
              shadowColor: const Color(0x5538B9C5),
              child: const Center(
                child: Icon(Icons.add_rounded, color: Colors.white, size: 34),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

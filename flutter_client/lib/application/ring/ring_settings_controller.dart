import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/ring/ring_contract_enums.dart';
import '../../native_contract/ring/ring_request_dtos.dart';
import '../../native_contract/ring/ring_state_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'ring_snapshot_tracker.dart';

enum RingSettingsLoadStatus { idle, loading, ready, error }

class RingSettingsController extends ChangeNotifier {
  RingSettingsController({required RingNativeGateway gateway})
    : _gateway = gateway;

  final RingNativeGateway _gateway;
  final RingSnapshotTracker _tracker = RingSnapshotTracker();
  StreamSubscription<RingStateEvent>? _subscription;
  bool _disposed = false;
  bool _isBusy = false;
  RingSettingsLoadStatus _status = RingSettingsLoadStatus.idle;
  String? _errorMessage;
  String? _notice;

  RingSettingsLoadStatus get status => _status;
  RingStateSnapshotDto? get snapshot => _tracker.current;
  RingSettingsDto? get settings => snapshot?.settings;
  RingCapabilitySnapshotDto? get capability => snapshot?.capability;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get notice => _notice;

  Future<void> initialize() async {
    if (_subscription != null) return;
    _status = RingSettingsLoadStatus.loading;
    _notify();
    _subscription = _gateway.stateEvents().listen(_handleEvent);
    await refresh();
  }

  Future<void> refresh() async {
    final invocation = await _gateway.getState();
    if (_disposed) return;
    if (!_acceptInvocation(invocation)) {
      _status = RingSettingsLoadStatus.error;
      _errorMessage = _messageFor(invocation, fallback: '无法读取响铃设置');
      _notify();
      return;
    }
    _status = RingSettingsLoadStatus.ready;
    _errorMessage = null;
    _notify();
  }

  Future<void> pickRingtone() async {
    final current = settings;
    if (current == null || _isBusy) return;
    await _run<PickRingtoneResponseDto>(
      () => _gateway.pickRingtone(
        PickRingtoneRequestDto(expectedSettingsRevision: current.revision),
      ),
      onSuccess: (response) {
        _tracker.accept(response.state);
        _notice =
            response.selectionStatus == RingRingtoneSelectionStatus.cancelled
            ? '已取消选择铃声'
            : '铃声已更新';
      },
      fallback: '无法打开系统铃声选择器',
    );
  }

  Future<void> setStrongReminderEnabled(bool enabled) async {
    final current = settings;
    if (current == null ||
        _isBusy ||
        current.strongReminderEnabled == enabled) {
      return;
    }
    await _run<RingStateSnapshotDto>(
      () => _gateway.updateSettings(
        UpdateRingSettingsRequestDto(
          expectedSettingsRevision: current.revision,
          strongReminderEnabled: enabled,
        ),
      ),
      onSuccess: _tracker.accept,
      fallback: '无法更新强提醒设置',
    );
  }

  Future<void> toggleTest() async {
    final current = snapshot;
    if (current == null || _isBusy || current.activeSession != null) return;
    final action = current.testState == RingTestState.audible
        ? RingTestAction.stop
        : RingTestAction.start;
    await _run<RingStateSnapshotDto>(
      () => _gateway.testRing(
        RingTestRequestDto(
          action: action,
          expectedSettingsRevision: current.settings.revision,
        ),
      ),
      onSuccess: _tracker.accept,
      fallback: action == RingTestAction.start ? '无法开始测试' : '无法停止测试',
    );
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  Future<void> _run<T>(
    Future<NativeInvocation<T>> Function() operation, {
    required void Function(T data) onSuccess,
    required String fallback,
  }) async {
    if (_isBusy) return;
    _isBusy = true;
    _errorMessage = null;
    _notice = null;
    _notify();
    final invocation = await operation();
    if (_disposed) return;
    final data = invocation.result.data;
    if (!invocation.result.ok || data == null) {
      _errorMessage = _messageFor(invocation, fallback: fallback);
    } else {
      onSuccess(data);
      _status = RingSettingsLoadStatus.ready;
    }
    _isBusy = false;
    _notify();
  }

  bool _acceptInvocation(NativeInvocation<RingStateSnapshotDto> invocation) {
    final data = invocation.result.data;
    if (!invocation.result.ok || data == null) return false;
    _tracker.accept(data);
    return true;
  }

  void _handleEvent(RingStateEvent event) {
    if (_disposed) return;
    switch (event) {
      case RingStateChanged(:final event):
        if (_tracker.accept(event.state)) {
          _status = RingSettingsLoadStatus.ready;
          _errorMessage = null;
          _notify();
        }
      case RingStateEventFailure(:final message):
        _errorMessage = '响铃状态更新无效：$message';
        _notify();
    }
  }

  static String _messageFor<T>(
    NativeInvocation<T> invocation, {
    required String fallback,
  }) {
    final error = invocation.result.error;
    return error == null ? fallback : '${error.code}: ${error.message}';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

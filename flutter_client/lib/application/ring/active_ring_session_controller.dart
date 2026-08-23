import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../gateway_interfaces/ring_native_gateway.dart';
import '../../native_contract/event/get_event_detail_request_dto.dart';
import '../../native_contract/ring/ring_request_dtos.dart';
import '../../native_contract/ring/ring_state_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'ring_snapshot_tracker.dart';

enum ActiveRingLoadStatus { idle, loading, ready, error }

class ActiveRingItemView {
  const ActiveRingItemView({
    required this.item,
    required this.title,
    required this.isDetailLoading,
    required this.detailUnavailable,
  });

  final ActiveRingItemDto item;
  final String title;
  final bool isDetailLoading;
  final bool detailUnavailable;

  ActiveRingItemView copyWith({
    String? title,
    bool? isDetailLoading,
    bool? detailUnavailable,
  }) => ActiveRingItemView(
    item: item,
    title: title ?? this.title,
    isDetailLoading: isDetailLoading ?? this.isDetailLoading,
    detailUnavailable: detailUnavailable ?? this.detailUnavailable,
  );
}

class ActiveRingSessionController extends ChangeNotifier {
  ActiveRingSessionController({
    required RingNativeGateway ringGateway,
    required EventNativeGateway eventGateway,
  }) : _ringGateway = ringGateway,
       _eventGateway = eventGateway;

  final RingNativeGateway _ringGateway;
  final EventNativeGateway _eventGateway;
  final RingSnapshotTracker _tracker = RingSnapshotTracker();
  final Map<String, ActiveRingItemView> _itemViews = {};
  StreamSubscription<RingStateEvent>? _subscription;
  bool _disposed = false;
  bool _isActionRunning = false;
  ActiveRingLoadStatus _status = ActiveRingLoadStatus.idle;
  String? _errorMessage;
  String? _notice;

  ActiveRingLoadStatus get status => _status;
  RingStateSnapshotDto? get snapshot => _tracker.current;
  ActiveRingSessionDto? get activeSession => snapshot?.activeSession;
  bool get hasActiveSession => activeSession != null;
  bool get isActionRunning => _isActionRunning;
  String? get errorMessage => _errorMessage;
  String? get notice => _notice;
  List<ActiveRingItemView> get items {
    final session = activeSession;
    if (session == null) return const [];
    return List.unmodifiable(
      session.items.map(
        (item) =>
            _itemViews[item.deliveryId] ??
            ActiveRingItemView(
              item: item,
              title: '正在读取日程…',
              isDetailLoading: true,
              detailUnavailable: false,
            ),
      ),
    );
  }

  Future<void> initialize() async {
    if (_subscription != null) return;
    _status = ActiveRingLoadStatus.loading;
    _notify();
    _subscription = _ringGateway.stateEvents().listen(_handleEvent);
    await refresh();
  }

  Future<void> refresh() async {
    final invocation = await _ringGateway.getState();
    if (_disposed) return;
    final data = invocation.result.data;
    if (!invocation.result.ok || data == null) {
      _status = ActiveRingLoadStatus.error;
      _errorMessage = _messageFor(invocation, fallback: '无法读取活动响铃');
      _notify();
      return;
    }
    _acceptSnapshot(data);
    _status = ActiveRingLoadStatus.ready;
    _errorMessage = null;
    _notify();
  }

  Future<void> stopItem(String deliveryId) => _stop([deliveryId]);

  Future<void> stopAll() {
    final ids = activeSession?.items
        .map((item) => item.deliveryId)
        .toList(growable: false);
    return ids == null || ids.isEmpty ? Future.value() : _stop(ids);
  }

  Future<void> snoozeItem(String deliveryId) => _snooze([deliveryId]);

  Future<void> snoozeAll() {
    final ids = activeSession?.items
        .map((item) => item.deliveryId)
        .toList(growable: false);
    return ids == null || ids.isEmpty ? Future.value() : _snooze(ids);
  }

  Future<void> completeItem(String deliveryId) async {
    final identity = _identity();
    if (identity == null || _isActionRunning) return;
    await _runStateAction(
      () => _ringGateway.completeItem(
        CompleteRingItemRequestDto(
          runtimeInstanceId: identity.runtimeInstanceId,
          sessionId: identity.sessionId,
          expectedSessionRevision: identity.revision,
          deliveryId: deliveryId,
        ),
      ),
      fallback: '无法完成该日程',
    );
  }

  Future<void> _stop(List<String> deliveryIds) async {
    final request = _itemsRequest(deliveryIds);
    if (request == null || _isActionRunning) return;
    await _runStateAction(
      () => _ringGateway.stopActive(request),
      fallback: '无法关闭响铃',
    );
  }

  Future<void> _snooze(List<String> deliveryIds) async {
    final request = _itemsRequest(deliveryIds);
    if (request == null || _isActionRunning) return;
    _beginAction();
    final invocation = await _ringGateway.snoozeActive(request);
    if (_disposed) return;
    final data = invocation.result.data;
    if (!invocation.result.ok || data == null) {
      _errorMessage = _messageFor(invocation, fallback: '无法稍后提醒');
    } else {
      _acceptSnapshot(data.state);
      if (data.failedCount > 0) {
        _notice = '${data.failedCount} 项稍后提醒失败，失败项仍保留在当前页面';
      }
    }
    _endAction();
  }

  Future<void> _runStateAction(
    Future<NativeInvocation<RingStateSnapshotDto>> Function() operation, {
    required String fallback,
  }) async {
    _beginAction();
    final invocation = await operation();
    if (_disposed) return;
    final data = invocation.result.data;
    if (!invocation.result.ok || data == null) {
      _errorMessage = _messageFor(invocation, fallback: fallback);
    } else {
      _acceptSnapshot(data);
    }
    _endAction();
  }

  void _beginAction() {
    _isActionRunning = true;
    _errorMessage = null;
    _notice = null;
    _notify();
  }

  void _endAction() {
    _isActionRunning = false;
    _notify();
  }

  _RingSessionIdentity? _identity() {
    final current = snapshot;
    final session = current?.activeSession;
    if (current == null || session == null) return null;
    return _RingSessionIdentity(
      runtimeInstanceId: current.runtimeInstanceId,
      sessionId: session.sessionId,
      revision: session.revision,
    );
  }

  ActiveRingItemsRequestDto? _itemsRequest(List<String> ids) {
    final identity = _identity();
    if (identity == null || ids.isEmpty) return null;
    return ActiveRingItemsRequestDto(
      runtimeInstanceId: identity.runtimeInstanceId,
      sessionId: identity.sessionId,
      expectedSessionRevision: identity.revision,
      deliveryIds: ids,
    );
  }

  void _handleEvent(RingStateEvent event) {
    if (_disposed) return;
    switch (event) {
      case RingStateChanged(:final event):
        if (_acceptSnapshot(event.state)) {
          _status = ActiveRingLoadStatus.ready;
          _errorMessage = null;
          _notify();
        }
      case RingStateEventFailure(:final message):
        _errorMessage = '响铃状态更新无效：$message';
        _notify();
    }
  }

  bool _acceptSnapshot(RingStateSnapshotDto candidate) {
    if (!_tracker.accept(candidate)) return false;
    _syncItemViews(candidate.activeSession?.items ?? const []);
    return true;
  }

  void _syncItemViews(List<ActiveRingItemDto> items) {
    final activeIds = items.map((item) => item.deliveryId).toSet();
    _itemViews.removeWhere((id, _) => !activeIds.contains(id));
    for (final item in items) {
      final existing = _itemViews[item.deliveryId];
      if (existing != null && existing.item.eventId == item.eventId) continue;
      _itemViews[item.deliveryId] = ActiveRingItemView(
        item: item,
        title: '正在读取日程…',
        isDetailLoading: true,
        detailUnavailable: false,
      );
      unawaited(_loadEventDetail(item));
    }
  }

  Future<void> _loadEventDetail(ActiveRingItemDto item) async {
    final invocation = await _eventGateway.getEventDetail(
      GetEventDetailRequestDto(id: item.eventId),
    );
    if (_disposed) return;
    final current = _itemViews[item.deliveryId];
    if (current == null || current.item.eventId != item.eventId) return;
    final detail = invocation.result.data;
    _itemViews[item.deliveryId] = current.copyWith(
      title: invocation.result.ok && detail != null
          ? detail.event.title
          : '日程详情暂不可用',
      isDetailLoading: false,
      detailUnavailable: !invocation.result.ok || detail == null,
    );
    _notify();
  }

  void clearMessages() {
    if (_notice == null && _errorMessage == null) return;
    _notice = null;
    _errorMessage = null;
    _notify();
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

class _RingSessionIdentity {
  const _RingSessionIdentity({
    required this.runtimeInstanceId,
    required this.sessionId,
    required this.revision,
  });

  final String runtimeInstanceId;
  final String sessionId;
  final int revision;
}

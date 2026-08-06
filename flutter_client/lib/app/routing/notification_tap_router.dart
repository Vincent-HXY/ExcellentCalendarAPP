import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/notification/notification_tap_payload_dto.dart';
import 'app_route_navigator.dart';

typedef NotificationRoutingLogger = void Function(String message);

class NotificationTapRouter {
  NotificationTapRouter({
    required AppRouteNavigator navigator,
    NotificationRoutingLogger? logger,
    this.maxRememberedPayloads = 128,
  }) : _navigator = navigator,
       _logger = logger ?? _defaultLogger;

  final AppRouteNavigator _navigator;
  final NotificationRoutingLogger _logger;
  final int maxRememberedPayloads;
  final Set<String> _handledDeliveryIds = {};
  final Queue<String> _handledDeliveries = Queue();

  bool open(NotificationTapPayloadDto payload) {
    if (_handledDeliveryIds.contains(payload.deliveryId)) {
      _logger(
        'Duplicate notification delivery tap ignored: ${payload.deliveryId}',
      );
      return false;
    }
    _remember(payload.deliveryId);

    final route = switch (payload.targetType) {
      NotificationTargetType.event => _detailRoute(
        targetType: 'event',
        targetId: payload.targetId,
        occurrenceKey: payload.occurrenceKey,
      ),
      NotificationTargetType.habit => _detailRoute(
        targetType: 'habit',
        targetId: payload.targetId,
      ),
      NotificationTargetType.anniversary => _detailRoute(
        targetType: 'anniversary',
        targetId: payload.targetId,
      ),
      NotificationTargetType.reminderRecoveryBatch => '/today',
    };
    _navigator.go(route);
    return true;
  }

  void fallback(String reason) {
    _logger('Notification tap fallback: $reason');
    _navigator.go('/today');
  }

  String _detailRoute({
    required String targetType,
    required String targetId,
    String? occurrenceKey,
  }) {
    final uri = Uri(
      pathSegments: [targetType, 'detail', targetId],
      queryParameters: occurrenceKey == null || occurrenceKey.isEmpty
          ? null
          : {'occurrence_key': occurrenceKey},
    );
    return '/$uri';
  }

  void _remember(String deliveryId) {
    _handledDeliveryIds.add(deliveryId);
    _handledDeliveries.addLast(deliveryId);
    while (_handledDeliveries.length > maxRememberedPayloads) {
      _handledDeliveryIds.remove(_handledDeliveries.removeFirst());
    }
  }

  static void _defaultLogger(String message) {
    debugPrint(message);
  }
}

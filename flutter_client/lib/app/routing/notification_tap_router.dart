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
  final Set<String> _handledIds = {};
  final Queue<Set<String>> _handledPayloads = Queue();

  bool open(NotificationTapPayloadDto payload) {
    final identifiers = <String>{
      'notification:${payload.notificationId}',
      if (payload.reminderId != null) 'reminder:${payload.reminderId}',
    };
    if (identifiers.any(_handledIds.contains)) {
      _logger('Duplicate notification tap ignored: ${payload.notificationId}');
      return false;
    }
    _remember(identifiers);

    final targetId = Uri.encodeComponent(payload.targetId);
    final route = switch (payload.targetType) {
      NotificationTargetType.event => '/event/detail/$targetId',
      NotificationTargetType.habit => '/habit/detail/$targetId',
      NotificationTargetType.anniversary => '/anniversary/detail/$targetId',
      NotificationTargetType.reminderRecoveryBatch => '/today',
    };
    _navigator.go(route);
    return true;
  }

  void fallback(String reason) {
    _logger('Notification tap fallback: $reason');
    _navigator.go('/today');
  }

  void _remember(Set<String> identifiers) {
    _handledIds.addAll(identifiers);
    _handledPayloads.addLast(identifiers);
    while (_handledPayloads.length > maxRememberedPayloads) {
      _handledIds.removeAll(_handledPayloads.removeFirst());
    }
  }

  static void _defaultLogger(String message) {
    debugPrint(message);
  }
}

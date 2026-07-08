class NativeMethodChannelNames {
  const NativeMethodChannelNames._();

  static const native = 'excellent_calendar/native';
  static const notificationOpened =
      'excellent_calendar/events/notification_opened';
}

class NativeEventMethods {
  const NativeEventMethods._();

  static const create = 'event.create';
  static const update = 'event.update';
  static const search = 'event.search';
  static const complete = 'event.complete';
  static const reopen = 'event.reopen';
}

class NativeReminderMethods {
  const NativeReminderMethods._();

  static const create = 'reminder.create';
  static const cancel = 'reminder.cancel';
  static const schedulePending = 'reminder.schedule_pending';
  static const reconcileSchedule = 'reminder.reconcile_schedule';
}

class NativeNotificationMethods {
  const NativeNotificationMethods._();

  static const initialize = 'notification.initialize';
  static const permissionStatus = 'notification.permission_status';
  static const requestPermission = 'notification.request_permission';
  static const openSettings = 'notification.open_settings';
  static const getInitialTapPayload = 'notification.get_initial_tap_payload';
}

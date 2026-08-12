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
  static const delete = 'event.delete';
  static const search = 'event.search';
  static const detail = 'event.detail';
  static const complete = 'event.complete';
  static const reopen = 'event.reopen';
  static const listOccurrences = 'event.list_occurrences';
  static const completeSeries = 'event.complete_series';
  static const reopenSeries = 'event.reopen_series';
  static const cancelSeries = 'event.cancel_series';
}

class NativeRuntimeMethods {
  const NativeRuntimeMethods._();

  static const deviceTimezone = 'runtime.device_timezone';
  static const resolveLocalDateTime = 'runtime.resolve_local_datetime';
  static const localizeInstants = 'runtime.localize_instants';
}

class NativeEventOccurrenceMethods {
  const NativeEventOccurrenceMethods._();

  static const complete = 'event_occurrence.complete';
  static const reopen = 'event_occurrence.reopen';
  static const skip = 'event_occurrence.skip';
  static const cancel = 'event_occurrence.cancel';
}

class NativeReminderMethods {
  const NativeReminderMethods._();

  static const create = 'reminder.create';
  static const update = 'reminder.update';
  static const cancel = 'reminder.cancel';
  static const list = 'reminder.list';
  static const reconcileSchedule = 'reminder.reconcile_schedule';
}

class NativeAnniversaryMethods {
  const NativeAnniversaryMethods._();

  static const create = 'anniversary.create';
  static const update = 'anniversary.update';
  static const delete = 'anniversary.delete';
  static const detail = 'anniversary.detail';
  static const list = 'anniversary.list';
  static const previewCountdown = 'anniversary.preview_countdown';
}

class NativeCategoryMethods {
  const NativeCategoryMethods._();

  static const list = 'category.list';
  static const create = 'category.create';
}

class NativeNotificationMethods {
  const NativeNotificationMethods._();

  static const initialize = 'notification.initialize';
  static const permissionStatus = 'notification.permission_status';
  static const requestPermission = 'notification.request_permission';
  static const openSettings = 'notification.open_settings';
  static const getInitialTapPayload = 'notification.get_initial_tap_payload';
}

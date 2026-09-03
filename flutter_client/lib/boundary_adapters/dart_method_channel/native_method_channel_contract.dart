class NativeMethodChannelNames {
  const NativeMethodChannelNames._();

  static const native = 'excellent_calendar/native';
  static const notificationOpened =
      'excellent_calendar/events/notification_opened';
  static const ringState = 'excellent_calendar/events/ring_state';
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
  static const setRemindersEnabled = 'anniversary.set_reminders_enabled';
  static const listOccurrences = 'anniversary.list_occurrences';
}

class NativeHabitMethods {
  const NativeHabitMethods._();

  static const create = 'habit.create';
  static const update = 'habit.update';
  static const list = 'habit.list';
  static const detail = 'habit.detail';
  static const end = 'habit.end';
  static const delete = 'habit.delete';
  static const checkIn = 'habit.check_in';
  static const clearCheckIn = 'habit.clear_check_in';
  static const listDailyStatuses = 'habit.list_daily_statuses';
  static const setReminder = 'habit.set_reminder';
}

class NativeCalendarMethods {
  const NativeCalendarMethods._();

  static const rangeSummary = 'calendar.range_summary';
  static const listDayItems = 'calendar.list_day_items';
}

class NativeSearchMethods {
  const NativeSearchMethods._();

  static const query = 'search.query';
  static const getLocalHistory = 'search.get_local_history';
  static const replaceLocalHistory = 'search.replace_local_history';
}

class NativeAppearanceMethods {
  const NativeAppearanceMethods._();

  static const getLocal = 'appearance.get_local';
  static const updateLocal = 'appearance.update_local';
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

class NativeRingMethods {
  const NativeRingMethods._();

  static const getState = 'ring.get_state';
  static const pickRingtone = 'ring.pick_ringtone';
  static const updateSettings = 'ring.update_settings';
  static const test = 'ring.test';
  static const stopActive = 'ring.stop_active';
  static const snoozeActive = 'ring.snooze_active';
  static const completeItem = 'ring.complete_item';
}

class NativeAuthMethods {
  const NativeAuthMethods._();

  static const refreshTokenStore = 'auth.refresh_token.store';
  static const refreshTokenRead = 'auth.refresh_token.read';
  static const refreshTokenDelete = 'auth.refresh_token.delete';
  static const refreshTokenExists = 'auth.refresh_token.exists';
}

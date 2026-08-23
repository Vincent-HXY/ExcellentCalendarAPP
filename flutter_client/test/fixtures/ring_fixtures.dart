import 'package:excellent_calendar/native_contract/notification/notification_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_contract_enums.dart';
import 'package:excellent_calendar/native_contract/ring/ring_state_dtos.dart';

const runtimeId = '10000000-0000-4000-8000-000000000001';
const secondRuntimeId = '10000000-0000-4000-8000-000000000002';
const sessionId = '20000000-0000-4000-8000-000000000001';
const notificationId = '30000000-0000-4000-8000-000000000001';
const deliveryId = '40000000-0000-4000-8000-000000000001';
const secondDeliveryId = '40000000-0000-4000-8000-000000000002';
const deliveryAttemptId = '50000000-0000-4000-8000-000000000001';
const secondDeliveryAttemptId = '50000000-0000-4000-8000-000000000002';
const reminderId = '60000000-0000-4000-8000-000000000001';
const secondReminderId = '60000000-0000-4000-8000-000000000002';
const eventId = '70000000-0000-4000-8000-000000000001';
const secondEventId = '70000000-0000-4000-8000-000000000002';
const snoozedReminderId = '80000000-0000-4000-8000-000000000001';

RingStateSnapshotDto ringSnapshot({
  String runtimeInstanceId = runtimeId,
  int sequence = 1,
  int sessionRevision = 0,
  bool canEnableRing = true,
  List<RingCapabilityBlockingReason> blockingReasons = const [],
  List<RingCapabilityDegradationReason> degradationReasons = const [],
  List<ActiveRingItemDto>? activeItems,
  RingTestState testState = RingTestState.inactive,
  int settingsRevision = 1,
  bool strongReminderEnabled = false,
}) {
  final items = activeItems;
  final session = items == null
      ? null
      : ActiveRingSessionDto(
          sessionId: sessionId,
          revision: sessionRevision,
          phase: RingSessionPhase.audible,
          generation: 1,
          startedAt: DateTime.utc(2026, 8, 22, 8),
          phaseChangedAt: DateTime.utc(2026, 8, 22, 8),
          audibleStartedAt: DateTime.utc(2026, 8, 22, 8),
          audibleDeadlineAt: DateTime.utc(2026, 8, 22, 8, 5),
          quietSince: null,
          controlNotificationVisible: true,
          soundActive: true,
          vibrationActive: true,
          items: items,
        );
  return RingStateSnapshotDto(
    capturedAt: DateTime.utc(2026, 8, 22, 8),
    runtimeInstanceId: runtimeInstanceId,
    sequence: sequence,
    sessionRevision: sessionRevision,
    settings: RingSettingsDto(
      revision: settingsRevision,
      ringtoneDisplayName: '晨曦',
      ringtoneAvailable: true,
      strongReminderEnabled: strongReminderEnabled,
    ),
    capability: RingCapabilitySnapshotDto(
      evaluatedAt: DateTime.utc(2026, 8, 22, 8),
      sdkInt: 35,
      notificationPermission: NotificationPermissionStatus.granted,
      exactAlarmPermission: ExactAlarmPermissionStatus.granted,
      fullScreenIntentPermission: FullScreenIntentPermissionStatus.granted,
      canPostNotifications: canEnableRing,
      canScheduleExactAlarms: canEnableRing,
      canUseFullScreenIntent: true,
      ringChannelEnabled: canEnableRing,
      hasAudioOutput: true,
      hasVibrator: true,
      canEnableRing: canEnableRing,
      blockingReasons: blockingReasons,
      degradationReasons: degradationReasons,
    ),
    activeSession: session,
    testState: items == null ? testState : RingTestState.inactive,
  );
}

ActiveRingItemDto ringItem({
  String itemDeliveryId = deliveryId,
  String itemAttemptId = deliveryAttemptId,
  String itemReminderId = reminderId,
  String itemEventId = eventId,
}) => ActiveRingItemDto(
  notificationId: notificationId,
  deliveryId: itemDeliveryId,
  deliveryAttemptId: itemAttemptId,
  reminderId: itemReminderId,
  eventId: itemEventId,
  recoveryBatchId: null,
  plannedAt: DateTime.utc(2026, 8, 22, 8),
  addedAt: DateTime.utc(2026, 8, 22, 8),
);

Map<String, dynamic> ringStateJson({
  int sequence = 1,
  int sessionRevision = 0,
  Object? activeSession,
  String testState = 'inactive',
}) => {
  'captured_at': '2026-08-22T08:00:00Z',
  'runtime_instance_id': runtimeId,
  'sequence': sequence,
  'session_revision': sessionRevision,
  'settings': {
    'revision': 1,
    'ringtone_display_name': '晨曦',
    'ringtone_available': true,
    'strong_reminder_enabled': false,
  },
  'capability': {
    'evaluated_at': '2026-08-22T08:00:00Z',
    'sdk_int': 35,
    'notification_permission': 'granted',
    'exact_alarm_permission': 'granted',
    'full_screen_intent_permission': 'granted',
    'can_post_notifications': true,
    'can_schedule_exact_alarms': true,
    'can_use_full_screen_intent': true,
    'ring_channel_enabled': true,
    'has_audio_output': true,
    'has_vibrator': true,
    'can_enable_ring': true,
    'blocking_reasons': <String>[],
    'degradation_reasons': <String>[],
  },
  'active_session': activeSession,
  'test_state': testState,
};

Map<String, dynamic> activeSessionJson({
  int revision = 1,
  List<Map<String, dynamic>>? items,
}) => {
  'session_id': sessionId,
  'revision': revision,
  'phase': 'audible',
  'generation': 1,
  'started_at': '2026-08-22T08:00:00Z',
  'phase_changed_at': '2026-08-22T08:00:00Z',
  'audible_started_at': '2026-08-22T08:00:00Z',
  'audible_deadline_at': '2026-08-22T08:05:00Z',
  'quiet_since': null,
  'control_notification_visible': true,
  'sound_active': true,
  'vibration_active': true,
  'items': items ?? [activeItemJson()],
};

Map<String, dynamic> activeItemJson({
  String itemDeliveryId = deliveryId,
  String itemAttemptId = deliveryAttemptId,
  String itemReminderId = reminderId,
  String itemEventId = eventId,
}) => {
  'notification_id': notificationId,
  'delivery_id': itemDeliveryId,
  'delivery_attempt_id': itemAttemptId,
  'reminder_id': itemReminderId,
  'event_id': itemEventId,
  'recovery_batch_id': null,
  'planned_at': '2026-08-22T08:00:00Z',
  'added_at': '2026-08-22T08:00:00Z',
};

Map<String, Object?> nativeSuccess(Object? data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'ring-request-1',
};

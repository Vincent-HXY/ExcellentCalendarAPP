enum FullScreenIntentPermissionStatus {
  granted('granted'),
  denied('denied'),
  notRequired('not_required'),
  unknown('unknown');

  const FullScreenIntentPermissionStatus(this.wireValue);
  final String wireValue;

  static FullScreenIntentPermissionStatus fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown FullScreenIntentPermissionStatus: $value',
        ),
      );
}

enum RingSessionPhase {
  prepared('prepared'),
  audible('audible'),
  quietPending('quiet_pending');

  const RingSessionPhase(this.wireValue);
  final String wireValue;

  static RingSessionPhase fromWireValue(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown RingSessionPhase: $value'),
  );
}

enum RingTestState {
  inactive('inactive'),
  audible('audible');

  const RingTestState(this.wireValue);
  final String wireValue;

  static RingTestState fromWireValue(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown RingTestState: $value'),
  );
}

enum RingTestAction {
  start('start'),
  stop('stop');

  const RingTestAction(this.wireValue);
  final String wireValue;
}

enum RingRingtoneSelectionStatus {
  selected('selected'),
  cancelled('cancelled');

  const RingRingtoneSelectionStatus(this.wireValue);
  final String wireValue;

  static RingRingtoneSelectionStatus fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown RingRingtoneSelectionStatus: $value',
        ),
      );
}

enum RingCapabilityBlockingReason {
  notificationPermissionUnavailable('notification_permission_unavailable'),
  exactAlarmPermissionUnavailable('exact_alarm_permission_unavailable'),
  ringChannelUnavailable('ring_channel_unavailable'),
  noOutputAvailable('no_output_available');

  const RingCapabilityBlockingReason(this.wireValue);
  final String wireValue;

  static RingCapabilityBlockingReason fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown RingCapabilityBlockingReason: $value',
        ),
      );
}

enum RingCapabilityDegradationReason {
  fullScreenIntentUnavailable('full_screen_intent_unavailable'),
  selectedRingtoneUnavailable('selected_ringtone_unavailable'),
  audioOutputUnavailable('audio_output_unavailable'),
  vibrationUnavailable('vibration_unavailable');

  const RingCapabilityDegradationReason(this.wireValue);
  final String wireValue;

  static RingCapabilityDegradationReason fromWireValue(String value) =>
      values.firstWhere(
        (item) => item.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown RingCapabilityDegradationReason: $value',
        ),
      );
}

enum RingStateChangeReason {
  settingsChanged('settings_changed'),
  capabilityChanged('capability_changed'),
  testChanged('test_changed'),
  sessionChanged('session_changed'),
  sessionRecovered('session_recovered');

  const RingStateChangeReason(this.wireValue);
  final String wireValue;

  static RingStateChangeReason fromWireValue(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () =>
        throw FormatException('Unknown RingStateChangeReason: $value'),
  );
}

enum RingItemActionStatus {
  succeeded('succeeded'),
  failed('failed');

  const RingItemActionStatus(this.wireValue);
  final String wireValue;

  static RingItemActionStatus fromWireValue(String value) => values.firstWhere(
    (item) => item.wireValue == value,
    orElse: () => throw FormatException('Unknown RingItemActionStatus: $value'),
  );
}

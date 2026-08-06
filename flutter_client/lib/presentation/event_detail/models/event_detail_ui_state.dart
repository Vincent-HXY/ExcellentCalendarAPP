import '../../../native_contract/event/event_response_dto.dart';
import '../../../application/timezone/timezone_application_service.dart';
import '../../../native_contract/runtime/local_wall_date_time.dart';

enum EventDisplayStatus {
  pending,
  inProgress,
  overdue,
  completed,
  cancelled,
  archived,
}

enum EventDetailField { schedule, note, allDay }

class EventDetailCompletionResult {
  const EventDetailCompletionResult._({
    required this.succeeded,
    this.errorMessage,
  });

  const EventDetailCompletionResult.success() : this._(succeeded: true);

  const EventDetailCompletionResult.failure(String message)
    : this._(succeeded: false, errorMessage: message);

  final bool succeeded;
  final String? errorMessage;
}

class ReminderUiModel {
  const ReminderUiModel({this.advanceMinutes, this.remindAt});

  final int? advanceMinutes;
  final DateTime? remindAt;

  String displayText(DateTime startAt) {
    final minutes =
        advanceMinutes ??
        (remindAt == null ? null : startAt.difference(remindAt!).inMinutes);
    if (minutes == null) return '\u4e0d\u63d0\u9192';
    if (minutes == 0) return '\u65e5\u7a0b\u53d1\u751f\u65f6';
    if (minutes % 1440 == 0) return '${minutes ~/ 1440} \u5929\u524d';
    if (minutes % 60 == 0) return '${minutes ~/ 60} \u5c0f\u65f6\u524d';
    return '$minutes \u5206\u949f\u524d';
  }
}

class EventDetailUiState {
  const EventDetailUiState({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.timezone,
    required this.isAllDay,
    required this.displayStatus,
    required this.priorityLabel,
    required this.reminders,
    this.description,
    this.content,
    this.participantCount,
    this.location,
  }) : completionPercent = displayStatus == EventDisplayStatus.completed
           ? 100
           : 0;

  final String eventId;
  final String title;
  final String? description;
  final String? content;
  final DateTime startAt;
  final DateTime endAt;
  final String timezone;
  final bool isAllDay;
  final EventDisplayStatus displayStatus;
  final int completionPercent;
  final String priorityLabel;
  final int? participantCount;
  final String? location;
  final List<ReminderUiModel> reminders;

  String get displayStatusLabel => switch (displayStatus) {
    EventDisplayStatus.pending => '\u5f85\u5b8c\u6210',
    EventDisplayStatus.inProgress => '\u8fdb\u884c\u4e2d',
    EventDisplayStatus.overdue => '\u5df2\u903e\u671f',
    EventDisplayStatus.completed => '\u5df2\u5b8c\u6210',
    EventDisplayStatus.cancelled => '\u5df2\u53d6\u6d88',
    EventDisplayStatus.archived => '\u5df2\u5f52\u6863',
  };

  String get completionLabel => switch (displayStatus) {
    EventDisplayStatus.completed => '\u5df2\u5b8c\u6210',
    EventDisplayStatus.cancelled => '\u5df2\u53d6\u6d88',
    EventDisplayStatus.archived => '\u5df2\u5f52\u6863',
    _ => '\u672a\u5b8c\u6210',
  };

  String get reminderLabel => reminders.isEmpty
      ? '\u4e0d\u63d0\u9192'
      : reminders.first.displayText(startAt);

  factory EventDetailUiState.fromEvent(
    EventResponseDto event, {
    required LocalizedTimeRange localizedTimeRange,
    List<ReminderUiModel> reminders = const [],
    int? participantCount,
    DateTime? now,
    LocalWallDateTime? referenceLocalNow,
    EventDisplayStatus? displayStatusOverride,
  }) {
    if (localizedTimeRange.timezone != event.timezone) {
      throw const FormatException(
        'Localized Event time must use the Event original timezone.',
      );
    }
    return EventDetailUiState(
      eventId: event.id,
      title: event.title,
      description: event.content,
      content: event.content,
      startAt: localizedTimeRange.start.toComponentDateTime(),
      endAt: localizedTimeRange.end.toComponentDateTime(),
      timezone: event.timezone,
      isAllDay: event.isAllDay,
      displayStatus:
          displayStatusOverride ??
          (referenceLocalNow == null
              ? deriveDisplayStatus(event: event, now: now)
              : deriveLocalizedDisplayStatus(
                  event: event,
                  localizedTimeRange: localizedTimeRange,
                  referenceLocalNow: referenceLocalNow,
                )),
      priorityLabel: priorityLabelForImportance(event.importance),
      participantCount: participantCount,
      location: event.location,
      reminders: reminders,
    );
  }

  factory EventDetailUiState.preview({String eventId = 'preview-event'}) {
    return EventDetailUiState(
      eventId: eventId,
      title: '\u4ea7\u54c1\u9700\u6c42\u8bc4\u5ba1',
      description:
          '\u9700\u6c42\u8bc4\u5ba1\u4f1a\u8bae\uff0c\u786e\u8ba4\u6838\u5fc3\u529f\u80fd\u8303\u56f4\u4e0e\u4f18\u5148\u7ea7',
      content:
          '\u672c\u6b21\u8bc4\u5ba1\u56f4\u7ed5\u65b0\u7248\u4ea7\u54c1\u9700\u6c42\u6587\u6863\u5c55\u5f00\uff0c\u91cd\u70b9\u8ba8\u8bba\u6838\u5fc3\u6d41\u7a0b\u3001\u6280\u672f\u65b9\u6848\u548c\u4e0a\u7ebf\u8282\u594f\uff0c\u660e\u786e\u8d23\u4efb\u4eba\u4e0e\u4e0b\u4e00\u6b65\u8ba1\u5212\u3002',
      startAt: DateTime(2026, 7, 8, 17),
      endAt: DateTime(2026, 7, 8, 18),
      timezone: 'Asia/Shanghai',
      isAllDay: false,
      displayStatus: EventDisplayStatus.pending,
      priorityLabel: '\u9ad8',
      participantCount: 5,
      location: '\u4f1a\u8bae\u5ba4 A',
      reminders: const [ReminderUiModel(advanceMinutes: 15)],
    );
  }

  static EventDisplayStatus deriveDisplayStatus({
    required EventResponseDto event,
    DateTime? now,
  }) {
    if (event.status == 'completed') return EventDisplayStatus.completed;
    if (event.status == 'cancelled') return EventDisplayStatus.cancelled;
    if (event.status == 'archived') return EventDisplayStatus.archived;
    final instant = now ?? DateTime.now();
    if (instant.isBefore(event.displayStartAt)) {
      return EventDisplayStatus.pending;
    }
    if (!instant.isAfter(event.displayEndAt)) {
      return EventDisplayStatus.inProgress;
    }
    return EventDisplayStatus.overdue;
  }

  static EventDisplayStatus deriveLocalizedDisplayStatus({
    required EventResponseDto event,
    required LocalizedTimeRange localizedTimeRange,
    required LocalWallDateTime referenceLocalNow,
  }) {
    if (event.status == 'completed') return EventDisplayStatus.completed;
    if (event.status == 'cancelled') return EventDisplayStatus.cancelled;
    if (event.status == 'archived') return EventDisplayStatus.archived;
    if (localizedTimeRange.timezone != event.timezone) {
      throw const FormatException(
        'Localized Event time must use the Event original timezone.',
      );
    }
    if (referenceLocalNow.isBefore(localizedTimeRange.start)) {
      return EventDisplayStatus.pending;
    }
    if (!localizedTimeRange.end.isBefore(referenceLocalNow)) {
      return EventDisplayStatus.inProgress;
    }
    return EventDisplayStatus.overdue;
  }

  static String priorityLabelForImportance(String? importance) {
    return switch (importance) {
      'important_urgent' || 'important_noturgent' => '\u9ad8',
      'unimportant_urgent' => '\u4e2d',
      _ => '\u4f4e',
    };
  }
}

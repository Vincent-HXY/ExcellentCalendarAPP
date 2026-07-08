import '../shared/contract_json_object.dart';

class SchedulePendingRemindersRequestDto {
  const SchedulePendingRemindersRequestDto({
    required this.fromAt,
    required this.toAt,
    this.limit = 500,
    this.forceReschedule = false,
  });

  final DateTime fromAt;
  final DateTime toAt;
  final int limit;
  final bool forceReschedule;

  Map<String, dynamic> toJson() {
    if (!toAt.isAfter(fromAt)) {
      throw const FormatException('to_at must be after from_at.');
    }
    if (limit < 1 || limit > 500) {
      throw const FormatException('limit must be between 1 and 500.');
    }
    return {
      'from_at': fromAt.toUtc().toIso8601String(),
      'to_at': toAt.toUtc().toIso8601String(),
      'limit': limit,
      'force_reschedule': forceReschedule,
    };
  }
}

class SchedulePendingRemindersResponseDto {
  const SchedulePendingRemindersResponseDto({
    required this.scheduledCount,
    required this.skippedCount,
    required this.failedCount,
    required this.unsupportedMethodCount,
    required this.hasMore,
    required this.failedReminderIds,
    required this.unsupportedReminderIds,
  });

  final int scheduledCount;
  final int skippedCount;
  final int failedCount;
  final int unsupportedMethodCount;
  final bool hasMore;
  final List<String> failedReminderIds;
  final List<String> unsupportedReminderIds;

  factory SchedulePendingRemindersResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'scheduled_count',
      'skipped_count',
      'failed_count',
      'unsupported_method_count',
      'has_more',
      'failed_reminder_ids',
      'unsupported_reminder_ids',
    }, 'SchedulePendingRemindersResponse');
    ContractJsonObject.requireKeys(json, {
      'scheduled_count',
      'skipped_count',
      'failed_count',
      'unsupported_method_count',
      'has_more',
      'failed_reminder_ids',
      'unsupported_reminder_ids',
    }, 'SchedulePendingRemindersResponse');
    return SchedulePendingRemindersResponseDto(
      scheduledCount: _nonNegativeInt(json, 'scheduled_count'),
      skippedCount: _nonNegativeInt(json, 'skipped_count'),
      failedCount: _nonNegativeInt(json, 'failed_count'),
      unsupportedMethodCount: _nonNegativeInt(json, 'unsupported_method_count'),
      hasMore: _bool(json, 'has_more'),
      failedReminderIds: _uniqueIds(json, 'failed_reminder_ids'),
      unsupportedReminderIds: _uniqueIds(json, 'unsupported_reminder_ids'),
    );
  }

  static int _nonNegativeInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int && value >= 0) return value;
    throw FormatException('$key must be non-negative integer.');
  }

  static bool _bool(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('$key must be bool.');
  }

  static List<String> _uniqueIds(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List ||
        value.any((item) => item is! String || item.isEmpty)) {
      throw FormatException('$key must be non-empty string array.');
    }
    final ids = value.cast<String>();
    if (ids.toSet().length != ids.length) {
      throw FormatException('$key must contain unique values.');
    }
    return List.unmodifiable(ids);
  }
}

import '../../native_contract/recurrence/recurrence_rule_dto.dart';
import '../../native_contract/reminder/reminder_draft_request_dto.dart';

enum RecurrencePreset { once, daily, weekly, monthly, yearly, custom }

extension RecurrencePresetLabel on RecurrencePreset {
  String get label {
    return switch (this) {
      RecurrencePreset.once => '仅一次',
      RecurrencePreset.daily => '每天',
      RecurrencePreset.weekly => '每周',
      RecurrencePreset.monthly => '每月',
      RecurrencePreset.yearly => '每年',
      RecurrencePreset.custom => '自定义',
    };
  }

  String? get contractFrequency {
    return switch (this) {
      RecurrencePreset.once => null,
      RecurrencePreset.daily => 'daily',
      RecurrencePreset.weekly => 'weekly',
      RecurrencePreset.monthly => 'monthly',
      RecurrencePreset.yearly => 'yearly',
      RecurrencePreset.custom => null,
    };
  }

  RecurrenceRuleDto? toDto() {
    final frequency = contractFrequency;
    if (frequency == null) {
      return null;
    }
    return RecurrenceRuleDto(frequency: frequency, interval: 1);
  }
}

enum ReminderPreset {
  atStart,
  minutes15,
  minutes30,
  hour1,
  hours2,
  day1,
  days2,
  week1,
  remainingTenPercent,
  custom,
}

extension ReminderPresetLabel on ReminderPreset {
  String get label {
    return switch (this) {
      ReminderPreset.atStart => '日程发生时',
      ReminderPreset.minutes15 => '15 分钟前',
      ReminderPreset.minutes30 => '30 分钟前',
      ReminderPreset.hour1 => '1 小时前',
      ReminderPreset.hours2 => '2 小时前',
      ReminderPreset.day1 => '1 天前',
      ReminderPreset.days2 => '2 天前',
      ReminderPreset.week1 => '1 周前',
      ReminderPreset.remainingTenPercent => '距日程开始剩余 10% 时',
      ReminderPreset.custom => '自定义',
    };
  }

  int? get fixedAdvanceMinutes {
    return switch (this) {
      ReminderPreset.atStart => 0,
      ReminderPreset.minutes15 => 15,
      ReminderPreset.minutes30 => 30,
      ReminderPreset.hour1 => 60,
      ReminderPreset.hours2 => 120,
      ReminderPreset.day1 => 1440,
      ReminderPreset.days2 => 2880,
      ReminderPreset.week1 => 10080,
      ReminderPreset.remainingTenPercent => null,
      ReminderPreset.custom => null,
    };
  }
}

String formatReminderAdvanceMinutes(int minutes) {
  if (minutes == 0) {
    return '日程发生时';
  }
  final days = minutes ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final remainingMinutes = minutes % 60;
  final parts = <String>[];
  if (days > 0) {
    parts.add('$days 天');
  }
  if (hours > 0) {
    parts.add('$hours 小时');
  }
  if (remainingMinutes > 0) {
    parts.add('$remainingMinutes 分钟');
  }
  return '${parts.join(' ')}前';
}

String reminderSummary({
  required Set<ReminderPreset> presets,
  required int? customAdvanceMinutes,
}) {
  if (presets.isEmpty) {
    return '不提醒';
  }
  if (presets.length == 1) {
    final preset = presets.first;
    if (preset == ReminderPreset.custom && customAdvanceMinutes != null) {
      return formatReminderAdvanceMinutes(customAdvanceMinutes);
    }
    return preset.label;
  }
  return '已设置 ${presets.length} 个提醒';
}

List<ReminderDraftRequestDto> buildReminderDraftDtos({
  required Set<ReminderPreset> presets,
  required int? customAdvanceMinutes,
  required bool isRingingEnabled,
}) {
  final methods = isRingingEnabled ? const ['popup', 'ring'] : const ['popup'];
  final drafts = <ReminderDraftRequestDto>[];
  for (final preset in presets) {
    final advanceMinutes = preset == ReminderPreset.custom
        ? customAdvanceMinutes
        : preset.fixedAdvanceMinutes;
    if (advanceMinutes == null) {
      continue;
    }
    drafts.add(
      ReminderDraftRequestDto(
        targetType: 'event',
        advanceMinutes: advanceMinutes,
        methods: methods,
        source: 'manual',
      ),
    );
  }
  return drafts;
}

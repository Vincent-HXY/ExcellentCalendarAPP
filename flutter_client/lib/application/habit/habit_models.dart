import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/habit/habit_contract_enums.dart';
import '../../native_contract/habit/habit_response_dtos.dart';

class HabitCardViewData {
  const HabitCardViewData({
    required this.id,
    required this.title,
    required this.lifecycle,
    required this.todayStatus,
    required this.targetCountHundredths,
    required this.completedCountHundredths,
    required this.todayNote,
    required this.hasTodayCheckIn,
    required this.unit,
    required this.challengeTimeProgress,
    required this.completionRate,
    required this.currentStreak,
    required this.remainingDays,
    required this.reminderEnabled,
    required this.reminderLocalTime,
  });

  final String id;
  final String title;
  final HabitLifecycleStatusContract lifecycle;
  final HabitDailyStatusContract? todayStatus;
  final int? targetCountHundredths;
  final int? completedCountHundredths;
  final String? todayNote;
  final bool hasTodayCheckIn;
  final String? unit;
  final double challengeTimeProgress;
  final double completionRate;
  final int currentStreak;
  final int remainingDays;
  final bool reminderEnabled;
  final String? reminderLocalTime;
  bool get isQuantitative => targetCountHundredths != null;
  int? get remainingCountHundredths {
    final target = targetCountHundredths;
    if (target == null) return null;
    final completed = completedCountHundredths ?? 0;
    return completed >= target ? 0 : target - completed;
  }

  bool get hasMetQuantitativeTarget =>
      isQuantitative && remainingCountHundredths == 0;
  bool get hasTodayQuantity => completedCountHundredths != null;
  bool get hasTodayNote => todayNote != null;
  bool get requiresClearConfirmation => hasTodayQuantity || hasTodayNote;
  bool get canMutateToday =>
      lifecycle == HabitLifecycleStatusContract.active &&
      todayStatus != HabitDailyStatusContract.upcoming;
  bool get quickActionClears =>
      !isQuantitative && todayStatus == HabitDailyStatusContract.done;

  factory HabitCardViewData.fromDto(HabitSummaryResponseDto dto) =>
      HabitCardViewData(
        id: dto.habit.id,
        title: dto.habit.title,
        lifecycle: dto.lifecycleStatus,
        todayStatus: dto.today?.status,
        targetCountHundredths: dto.habit.targetCountHundredths,
        completedCountHundredths: dto.today?.checkIn?.completedCountHundredths,
        todayNote: dto.today?.checkIn?.note,
        hasTodayCheckIn: dto.today?.checkIn != null,
        unit: dto.habit.unit,
        challengeTimeProgress: dto.challengeTimeProgress,
        completionRate: dto.statistics.completionRateAll,
        currentStreak: dto.statistics.currentStreak,
        remainingDays: dto.remainingDays,
        reminderEnabled: dto.reminderSettings.isEnabled,
        reminderLocalTime: dto.reminderSettings.template?.localTime,
      );
}

class HabitTodayProgressViewData {
  const HabitTodayProgressViewData({
    required this.asOfDate,
    required this.done,
    required this.eligible,
    required this.skipped,
  });
  final String asOfDate;
  final int done;
  final int eligible;
  final int skipped;

  factory HabitTodayProgressViewData.fromDto(
    HabitTodayProgressResponseDto dto,
  ) => HabitTodayProgressViewData(
    asOfDate: dto.asOfDate,
    done: dto.doneCount,
    eligible: dto.eligibleCount,
    skipped: dto.skippedCount,
  );
}

class HabitDetailViewData {
  HabitDetailViewData({required this.dto});
  final HabitDetailResponseDto dto;
  HabitResponseDto get habit => dto.habit;
  HabitLifecycleStatusContract get lifecycle => dto.lifecycleStatus;
  List<HabitDailyStatusResponseDto> get history => dto.history;
  bool get isReadOnly =>
      lifecycle == HabitLifecycleStatusContract.completed ||
      lifecycle == HabitLifecycleStatusContract.endedEarly;
}

String habitScheduleCapabilityMessage(
  HabitScheduleCapabilityResponseDto capability,
) => switch (capability.scheduleStatus) {
  HabitScheduleStatusContract.scheduledExact => '提醒已按精确时间安排',
  HabitScheduleStatusContract.scheduledApproximate => '提醒将以近似时间送达',
  HabitScheduleStatusContract.pendingPermission => '数据已保存，提醒等待系统授权',
  HabitScheduleStatusContract.pendingReconciliation => '数据已保存，提醒等待系统恢复',
  HabitScheduleStatusContract.notRequired => '数据已保存',
};

String habitReminderSummary(
  HabitReminderSettingsResponseDto settings, {
  HabitScheduleCapabilityResponseDto? capability,
}) {
  if (!settings.isEnabled) return '未开启';
  final time = settings.template?.localTime ?? '--:--';
  if (capability != null) {
    return '$time · ${habitScheduleCapabilityMessage(capability)}';
  }
  if (settings.scheduleReconciliationRequired) {
    return '$time · 提醒等待系统恢复';
  }
  return '$time · 提醒设置已保存';
}

String habitFailureMessage(Object error) {
  if (error is HabitGatewayFailure) {
    return switch (error.code) {
      'HABIT_NOT_FOUND' || 'HABIT_TARGET_DELETED' => '该习惯不存在或已删除',
      'HABIT_UPDATE_CONFLICT' => '习惯已在其他位置更新，请刷新后重试',
      'HABIT_TARGET_LOCKED' ||
      'HABIT_START_DATE_LOCKED' => '首次打卡后，目标、单位和开始日期不可修改',
      'HABIT_ALREADY_ENDED' => '挑战已结束，历史记录只读',
      'HABIT_NOT_STARTED' => '挑战尚未开始，不能提前结束',
      'HABIT_END_NOT_EARLY' => '今天是最终计划日，无需提前结束',
      'HABIT_CHECK_IN_FUTURE_DATE' => '不能为未来日期打卡',
      'HABIT_CHECK_IN_DATE_OUT_OF_RANGE' => '该日期不在挑战范围内',
      'HABIT_CHALLENGE_TOO_LONG' => '挑战期限不能超过 400 天',
      'HABIT_STATISTICS_OVERFLOW' => '累计数量超出可精确处理范围',
      'CONTRACT_VALIDATION_FAILED' ||
      'CONTRACT_VERSION_UNSUPPORTED' => '数据协议不兼容，请更新应用后重试',
      _ when error.retryable => '暂时无法完成，请重试',
      _ => error.message,
    };
  }
  return '发生未知错误，请重试';
}

String formatHundredths(int value) {
  final whole = value ~/ 100;
  final fraction = value.remainder(100).abs();
  return fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(2, '0')}';
}

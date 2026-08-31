import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/habit/habit_contract_enums.dart';
import '../../native_contract/habit/habit_request_dtos.dart';
import '../../native_contract/habit/habit_response_dtos.dart';
import 'habit_models.dart';

enum HabitDayPhase { loading, ready, missing, error }

class HabitDayController extends ChangeNotifier {
  HabitDayController({
    required this.habitId,
    required this.date,
    required HabitGateway gateway,
    required String Function() timezoneProvider,
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider;

  final String habitId;
  final String date;
  final HabitGateway _gateway;
  final String Function() _timezoneProvider;

  HabitDayPhase _phase = HabitDayPhase.loading;
  HabitDetailViewData? _detail;
  HabitDailyStatusResponseDto? _status;
  String? _errorMessage;
  bool _isMutating = false;
  int _loadGeneration = 0;
  int _mutationGeneration = 0;
  bool _disposed = false;

  HabitDayPhase get phase => _phase;
  HabitDetailViewData? get detail => _detail;
  HabitDailyStatusResponseDto? get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isMutating => _isMutating;
  bool get canMutate {
    final detail = _detail;
    final status = _status;
    if (_phase != HabitDayPhase.ready ||
        detail == null ||
        status == null ||
        detail.lifecycle != HabitLifecycleStatusContract.active ||
        status.status == HabitDailyStatusContract.upcoming) {
      return false;
    }
    return date.compareTo(detail.habit.startDate) >= 0 &&
        date.compareTo(detail.habit.endDate) <= 0;
  }

  String get readOnlyMessage {
    final detail = _detail;
    if (detail == null) return '当前日期状态尚未加载。';
    if (date.compareTo(detail.habit.startDate) < 0 ||
        date.compareTo(detail.habit.endDate) > 0) {
      return '该日期不在挑战范围内，当前记录只读。';
    }
    if (_status?.status == HabitDailyStatusContract.upcoming ||
        detail.lifecycle == HabitLifecycleStatusContract.upcoming) {
      return '日期尚未到达，当前记录只读。';
    }
    return '挑战已结束，历史记录只读。';
  }

  Future<void> initialize() => load();

  Future<void> load() async {
    if (_disposed || _isMutating) return;
    final generation = ++_loadGeneration;
    _phase = HabitDayPhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final detailDto = await _gateway.detail(
        GetHabitDetailRequestDto(id: habitId, timezone: _timezoneProvider()),
      );
      final daily = await _gateway.listDailyStatuses(
        ListHabitDailyStatusesRequestDto(
          habitId: habitId,
          startDate: date,
          endDate: date,
          timezone: _timezoneProvider(),
        ),
      );
      if (_disposed || generation != _loadGeneration || _isMutating) return;
      if (daily.habitId != habitId ||
          daily.startDate != date ||
          daily.endDate != date ||
          daily.items.length != 1 ||
          daily.items.single.date != date) {
        throw const HabitGatewayFailure(
          code: 'CONTRACT_VALIDATION_FAILED',
          message: 'Selected habit day projection differs from its request.',
          retryable: false,
        );
      }
      _detail = HabitDetailViewData(dto: detailDto);
      _status = daily.items.single;
      _phase = HabitDayPhase.ready;
    } catch (error) {
      if (_disposed || generation != _loadGeneration || _isMutating) return;
      if (error is HabitGatewayFailure &&
          {'HABIT_NOT_FOUND', 'HABIT_TARGET_DELETED'}.contains(error.code)) {
        _detail = null;
        _status = null;
        _phase = HabitDayPhase.missing;
      } else {
        _phase = HabitDayPhase.error;
      }
      _errorMessage = habitFailureMessage(error);
    }
    _notify();
  }

  Future<bool> set({
    required HabitCheckInStatusContract status,
    int? completedCountHundredths,
    String? note,
  }) => _mutate(
    () => _gateway.checkIn(
      HabitCheckInRequestDto(
        habitId: habitId,
        checkDate: date,
        status: status,
        completedCountHundredths: completedCountHundredths,
        note: note,
        timezone: _timezoneProvider(),
      ),
    ),
  );

  Future<bool> clear() => _mutate(
    () => _gateway.clearCheckIn(
      ClearHabitCheckInRequestDto(
        habitId: habitId,
        checkDate: date,
        timezone: _timezoneProvider(),
      ),
    ),
  );

  Future<bool> _mutate(
    Future<HabitCheckInMutationResponseDto> Function() operation,
  ) async {
    if (_disposed || _isMutating || !canMutate) return false;
    final mutation = ++_mutationGeneration;
    _isMutating = true;
    _errorMessage = null;
    _notify();
    try {
      final result = await operation();
      if (!_isCurrentMutation(mutation)) return false;
      if (result.dailyStatus.date != date) {
        _errorMessage = '数据协议不兼容，请更新应用后重试';
        return false;
      }
      _status = result.dailyStatus;
      return true;
    } catch (error) {
      if (_isCurrentMutation(mutation)) {
        _errorMessage = habitFailureMessage(error);
      }
      return false;
    } finally {
      if (_isCurrentMutation(mutation)) {
        _isMutating = false;
        _notify();
      }
    }
  }

  bool _isCurrentMutation(int mutation) =>
      !_disposed && _isMutating && mutation == _mutationGeneration;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration += 1;
    _mutationGeneration += 1;
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/habit/habit_contract_enums.dart';
import '../../native_contract/habit/habit_request_dtos.dart';
import '../../native_contract/habit/habit_response_dtos.dart';
import '../../native_contract/shared/civil_date.dart';
import 'habit_models.dart';

enum HabitDetailPhase { loading, ready, refreshing, missing, error }

class HabitDetailController extends ChangeNotifier {
  HabitDetailController({
    required this.habitId,
    required HabitGateway gateway,
    required String Function() timezoneProvider,
    this.focusOccurrenceKey,
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider;

  final String habitId;
  final String? focusOccurrenceKey;
  final HabitGateway _gateway;
  final String Function() _timezoneProvider;
  HabitDetailPhase _phase = HabitDetailPhase.loading;
  HabitDetailViewData? _detail;
  String? _errorMessage;
  int _loadGeneration = 0;
  int _mutationGeneration = 0;
  bool _isMutating = false;
  bool _disposed = false;

  HabitDetailPhase get phase => _phase;
  HabitDetailViewData? get detail => _detail;
  String? get errorMessage => _errorMessage;
  bool get isMutating => _isMutating;

  Future<void> initialize() => load();

  Future<void> load({bool preserve = false}) async {
    if (_disposed || _isMutating) return;
    final generation = ++_loadGeneration;
    _phase = preserve && _detail != null
        ? HabitDetailPhase.refreshing
        : HabitDetailPhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final dto = await _gateway.detail(
        GetHabitDetailRequestDto(id: habitId, timezone: _timezoneProvider()),
      );
      if (_disposed || generation != _loadGeneration || _isMutating) return;
      _detail = HabitDetailViewData(dto: dto);
      _phase = HabitDetailPhase.ready;
    } catch (error) {
      if (_disposed || generation != _loadGeneration || _isMutating) return;
      if (error is HabitGatewayFailure &&
          {'HABIT_NOT_FOUND', 'HABIT_TARGET_DELETED'}.contains(error.code)) {
        _detail = null;
        _phase = HabitDetailPhase.missing;
      } else {
        _errorMessage = habitFailureMessage(error);
        _phase = _detail == null
            ? HabitDetailPhase.error
            : HabitDetailPhase.ready;
      }
    }
    _notify();
  }

  Future<bool> setDay({
    required String date,
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

  Future<bool> clearDay(String date) => _mutate(
    () => _gateway.clearCheckIn(
      ClearHabitCheckInRequestDto(
        habitId: habitId,
        checkDate: date,
        timezone: _timezoneProvider(),
      ),
    ),
  );

  Future<bool> endEarly() {
    final current = _detail;
    if (current == null) return Future.value(false);
    return _mutate(
      () => _gateway.end(
        HabitOptimisticRequestDto(
          id: habitId,
          expectedUpdatedAt: current.habit.updatedAt,
          timezone: _timezoneProvider(),
        ),
      ),
    );
  }

  Future<bool> delete() async {
    final current = _detail;
    if (current == null) return false;
    final mutation = _startMutation();
    if (mutation == null) return false;
    try {
      await _gateway.delete(
        HabitOptimisticRequestDto(
          id: habitId,
          expectedUpdatedAt: current.habit.updatedAt,
          timezone: _timezoneProvider(),
        ),
      );
      return _isCurrentMutation(mutation);
    } catch (error) {
      if (_isCurrentMutation(mutation)) {
        _errorMessage = habitFailureMessage(error);
      }
      return false;
    } finally {
      _finishMutation(mutation);
    }
  }

  Future<HabitDailyStatusListResponseDto?> loadEarlierHistory({
    String? beforeDate,
  }) async {
    final current = _detail;
    if (current == null || !current.dto.hasEarlierHistory || _isMutating) {
      return null;
    }
    final generation = _loadGeneration;
    final end = CivilDate.parse(
      beforeDate ?? current.dto.historyStartDate!,
    ).addDays(-1);
    final challengeStart = CivilDate.parse(current.habit.startDate);
    if (end.compareTo(challengeStart) < 0) return null;
    final candidateStart = end.addDays(-29);
    final start = candidateStart.compareTo(challengeStart) < 0
        ? challengeStart
        : candidateStart;
    try {
      final response = await _gateway.listDailyStatuses(
        ListHabitDailyStatusesRequestDto(
          habitId: habitId,
          startDate: start.format(),
          endDate: end.format(),
          timezone: _timezoneProvider(),
        ),
      );
      if (_disposed || generation != _loadGeneration || _isMutating) {
        return null;
      }
      return response;
    } catch (error) {
      if (!_disposed && generation == _loadGeneration && !_isMutating) {
        _errorMessage = habitFailureMessage(error);
        _notify();
      }
      return null;
    }
  }

  Future<bool> _mutate(Future<Object> Function() operation) async {
    if (_detail == null) return false;
    final mutation = _startMutation();
    if (mutation == null) return false;
    try {
      await operation();
      if (!_isCurrentMutation(mutation)) return false;
      await _reloadAfterMutation(mutation);
      return _isCurrentMutation(mutation);
    } catch (error) {
      if (_isCurrentMutation(mutation)) {
        _errorMessage = habitFailureMessage(error);
      }
      return false;
    } finally {
      _finishMutation(mutation);
    }
  }

  int? _startMutation() {
    if (_disposed || _isMutating) return null;
    final mutation = ++_mutationGeneration;
    _loadGeneration += 1;
    _isMutating = true;
    _phase = HabitDetailPhase.ready;
    _errorMessage = null;
    _notify();
    return mutation;
  }

  Future<void> _reloadAfterMutation(int mutation) async {
    final generation = ++_loadGeneration;
    try {
      final dto = await _gateway.detail(
        GetHabitDetailRequestDto(id: habitId, timezone: _timezoneProvider()),
      );
      if (!_isCurrentMutation(mutation) || generation != _loadGeneration) {
        return;
      }
      _detail = HabitDetailViewData(dto: dto);
      _phase = HabitDetailPhase.ready;
    } catch (_) {
      if (!_isCurrentMutation(mutation) || generation != _loadGeneration) {
        return;
      }
      _phase = HabitDetailPhase.ready;
      _errorMessage = '操作已保存，但最新状态加载失败，请刷新。';
    }
  }

  bool _isCurrentMutation(int mutation) =>
      !_disposed && _isMutating && mutation == _mutationGeneration;

  void _finishMutation(int mutation) {
    if (!_isCurrentMutation(mutation)) return;
    _isMutating = false;
    _notify();
  }

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

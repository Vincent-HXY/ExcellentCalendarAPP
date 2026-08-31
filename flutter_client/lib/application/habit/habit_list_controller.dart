import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/habit_gateway.dart';
import '../../native_contract/common/pagination_request_dto.dart';
import '../../native_contract/habit/habit_contract_enums.dart';
import '../../native_contract/habit/habit_request_dtos.dart';
import 'habit_models.dart';

enum HabitListPhase { loading, empty, ready, refreshing, error }

class HabitListController extends ChangeNotifier {
  HabitListController({
    required HabitGateway gateway,
    required String Function() timezoneProvider,
    this.successFeedbackDelay = const Duration(milliseconds: 260),
  }) : _gateway = gateway,
       _timezoneProvider = timezoneProvider;

  final HabitGateway _gateway;
  final String Function() _timezoneProvider;
  final Duration successFeedbackDelay;
  HabitListPhase _phase = HabitListPhase.loading;
  List<HabitCardViewData> _items = const [];
  HabitTodayProgressViewData? _todayProgress;
  String? _errorMessage;
  bool _hasMore = false;
  String? _nextCursor;
  bool _loadingMore = false;
  String? _loadMoreErrorMessage;
  String? _listTimezone;
  final Set<String> _mutatingIds = {};
  final Set<String> _succeededIds = {};
  Future<bool> Function()? _retryMutation;
  int _generation = 0;
  bool _disposed = false;

  HabitListPhase get phase => _phase;
  List<HabitCardViewData> get items => _items;
  HabitTodayProgressViewData? get todayProgress => _todayProgress;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _loadingMore;
  String? get loadMoreErrorMessage => _loadMoreErrorMessage;
  Set<String> get mutatingIds => Set.unmodifiable(_mutatingIds);
  Set<String> get succeededIds => Set.unmodifiable(_succeededIds);
  bool get canRetryMutation => _retryMutation != null;

  List<HabitCardViewData> group(HabitLifecycleStatusContract status) =>
      _items.where((item) => item.lifecycle == status).toList(growable: false);

  Future<void> initialize() => load();

  Future<void> load({bool preserve = false}) async {
    final generation = ++_generation;
    final keep = preserve && _items.isNotEmpty;
    final timezone = _timezoneProvider();
    _phase = keep ? HabitListPhase.refreshing : HabitListPhase.loading;
    _errorMessage = null;
    _loadingMore = false;
    _loadMoreErrorMessage = null;
    _listTimezone = timezone;
    _notify();
    try {
      final result = await _gateway.list(
        ListHabitsRequestDto(
          timezone: timezone,
          pagination: const PaginationRequestDto(
            page: 1,
            pageSize: 100,
            sortBy: null,
            sortDirection: null,
          ),
        ),
      );
      if (_disposed || generation != _generation) return;
      _items = result.items.map(HabitCardViewData.fromDto).toList();
      _todayProgress = HabitTodayProgressViewData.fromDto(result.todayProgress);
      _setPagination(
        hasMore: result.pagination.hasMore,
        nextCursor: result.pagination.nextCursor,
      );
      _retryMutation = null;
      _phase = _items.isEmpty ? HabitListPhase.empty : HabitListPhase.ready;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _errorMessage = habitFailureMessage(error);
      _phase = keep ? HabitListPhase.ready : HabitListPhase.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (_disposed || _loadingMore || !_hasMore || cursor == null) return;
    final generation = _generation;
    final timezone = _listTimezone ?? _timezoneProvider();
    _loadingMore = true;
    _loadMoreErrorMessage = null;
    _notify();
    try {
      final result = await _gateway.list(
        ListHabitsRequestDto(
          timezone: timezone,
          pagination: PaginationRequestDto(
            page: null,
            pageSize: 100,
            cursor: cursor,
            sortBy: null,
            sortDirection: null,
          ),
        ),
      );
      if (_disposed || generation != _generation) return;
      if (result.pagination.hasMore && result.pagination.nextCursor == cursor) {
        throw StateError('Habit pagination cursor did not advance.');
      }
      final merged = <String, HabitCardViewData>{
        for (final item in _items) item.id: item,
      };
      for (final dto in result.items) {
        final item = HabitCardViewData.fromDto(dto);
        merged[item.id] = item;
      }
      _items = List.unmodifiable(merged.values);
      _setPagination(
        hasMore: result.pagination.hasMore,
        nextCursor: result.pagination.nextCursor,
      );
      _retryMutation = null;
      _phase = _items.isEmpty ? HabitListPhase.empty : HabitListPhase.ready;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _loadMoreErrorMessage = habitFailureMessage(error);
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _loadingMore = false;
        _notify();
      }
    }
  }

  Future<bool> quickCheckIn(
    HabitCardViewData item, {
    bool clearConfirmed = false,
  }) async {
    if (_disposed || !item.canMutateToday) return false;
    final date = _todayProgress?.asOfDate;
    if (date == null) return false;
    if (item.quickActionClears &&
        item.requiresClearConfirmation &&
        !clearConfirmed) {
      return false;
    }
    if (!_mutatingIds.add(item.id)) return false;
    _errorMessage = null;
    _retryMutation = null;
    _notify();
    try {
      if (item.isQuantitative) {
        final amount = (item.completedCountHundredths ?? 0) + 100;
        await _gateway.checkIn(
          HabitCheckInRequestDto(
            habitId: item.id,
            checkDate: date,
            status: amount < item.targetCountHundredths!
                ? HabitCheckInStatusContract.partial
                : HabitCheckInStatusContract.done,
            completedCountHundredths: amount,
            note: item.todayNote,
            timezone: _timezoneProvider(),
          ),
        );
      } else if (item.todayStatus == HabitDailyStatusContract.done) {
        await _gateway.clearCheckIn(
          ClearHabitCheckInRequestDto(
            habitId: item.id,
            checkDate: date,
            timezone: _timezoneProvider(),
          ),
        );
      } else {
        await _gateway.checkIn(
          HabitCheckInRequestDto(
            habitId: item.id,
            checkDate: date,
            status: HabitCheckInStatusContract.done,
            completedCountHundredths: null,
            note: null,
            timezone: _timezoneProvider(),
          ),
        );
      }
      if (_disposed) return false;
      _succeededIds.add(item.id);
      _notify();
      await Future<void>.delayed(successFeedbackDelay);
      if (_disposed) return false;
      _succeededIds.remove(item.id);
      await load(preserve: true);
      if (_disposed) return false;
      return true;
    } catch (error) {
      if (!_disposed) {
        _errorMessage = habitFailureMessage(error);
        _retryMutation = () =>
            quickCheckIn(item, clearConfirmed: clearConfirmed);
        _notify();
      }
      return false;
    } finally {
      if (!_disposed) {
        _mutatingIds.remove(item.id);
        _succeededIds.remove(item.id);
        _notify();
      }
    }
  }

  Future<bool> setExactQuantity(
    HabitCardViewData item,
    int hundredths, {
    bool clearConfirmed = false,
  }) async {
    if (_disposed || !item.isQuantitative || !item.canMutateToday) {
      return false;
    }
    final date = _todayProgress?.asOfDate;
    if (date == null) return false;
    if (hundredths == 0 && !item.hasTodayCheckIn) return true;
    if (hundredths == 0 && item.requiresClearConfirmation && !clearConfirmed) {
      return false;
    }
    if (!_mutatingIds.add(item.id)) return false;
    _errorMessage = null;
    _retryMutation = null;
    _notify();
    try {
      if (hundredths == 0) {
        await _gateway.clearCheckIn(
          ClearHabitCheckInRequestDto(
            habitId: item.id,
            checkDate: date,
            timezone: _timezoneProvider(),
          ),
        );
      } else {
        await _gateway.checkIn(
          HabitCheckInRequestDto(
            habitId: item.id,
            checkDate: date,
            status: hundredths < item.targetCountHundredths!
                ? HabitCheckInStatusContract.partial
                : HabitCheckInStatusContract.done,
            completedCountHundredths: hundredths,
            note: item.todayNote,
            timezone: _timezoneProvider(),
          ),
        );
      }
      if (_disposed) return false;
      _succeededIds.add(item.id);
      _notify();
      await Future<void>.delayed(successFeedbackDelay);
      if (_disposed) return false;
      _succeededIds.remove(item.id);
      await load(preserve: true);
      if (_disposed) return false;
      return true;
    } catch (error) {
      if (!_disposed) {
        _errorMessage = habitFailureMessage(error);
        _retryMutation = () =>
            setExactQuantity(item, hundredths, clearConfirmed: clearConfirmed);
        _notify();
      }
      return false;
    } finally {
      if (!_disposed) {
        _mutatingIds.remove(item.id);
        _succeededIds.remove(item.id);
        _notify();
      }
    }
  }

  Future<bool> retryLastMutation() async {
    if (_disposed) return false;
    final retry = _retryMutation;
    if (retry == null) return false;
    _retryMutation = null;
    _errorMessage = null;
    _notify();
    return retry();
  }

  void clearError() {
    _errorMessage = null;
    _retryMutation = null;
    _notify();
  }

  void _setPagination({required bool hasMore, required String? nextCursor}) {
    _hasMore = hasMore && nextCursor != null;
    _nextCursor = _hasMore ? nextCursor : null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}

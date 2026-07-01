import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/event/complete_event_use_case.dart';
import '../../application/event/read_events_use_case.dart';
import '../../native_contract/common/pagination_request_dto.dart';
import '../../native_contract/event/complete_event_request_dto.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/search_event_request_dto.dart';
import 'models/inbox_task_view_data.dart';

class InboxCompletionResult {
  const InboxCompletionResult._({required this.succeeded, this.errorMessage});

  const InboxCompletionResult.success() : this._(succeeded: true);

  const InboxCompletionResult.failure(String message)
    : this._(succeeded: false, errorMessage: message);

  final bool succeeded;
  final String? errorMessage;
}

class InboxController extends ChangeNotifier {
  InboxController({
    required ReadEventsUseCase readEventsUseCase,
    required CompleteEventUseCase completeEventUseCase,
  }) : _readEventsUseCase = readEventsUseCase,
       _completeEventUseCase = completeEventUseCase;

  final ReadEventsUseCase _readEventsUseCase;
  final CompleteEventUseCase _completeEventUseCase;

  List<InboxTaskViewData> _activeTasks = const [];
  List<InboxTaskViewData> _completedTasks = const [];
  int _completedCount = 0;
  final Set<String> _completingIds = <String>{};
  bool _isLoadingActive = false;
  bool _isLoadingCompleted = false;
  bool _hasLoadedCompleted = false;
  bool _isCompletedExpanded = false;
  bool _isDisposed = false;
  String? _activeError;
  String? _completedError;

  List<InboxTaskViewData> get activeTasks => _activeTasks;
  List<InboxTaskViewData> get completedTasks => _completedTasks;
  int get completedCount => _completedCount;
  bool get hasLoadedCompleted => _hasLoadedCompleted;
  String get completedCountLabel {
    if (!_hasLoadedCompleted && _isLoadingCompleted) {
      return '…';
    }
    if (!_hasLoadedCompleted && _completedError != null) {
      return '--';
    }
    return '$_completedCount';
  }

  Set<String> get completingIds => Set.unmodifiable(_completingIds);
  bool get isLoadingActive => _isLoadingActive;
  bool get isLoadingCompleted => _isLoadingCompleted;
  String? get activeError => _activeError;
  String? get completedError => _completedError;

  Future<void> initialize() async {
    await Future.wait([loadActive(), loadCompleted()]);
  }

  Future<void> loadActive() async {
    _isLoadingActive = true;
    _activeError = null;
    _notifyListeners();

    final invocation = await _readEventsUseCase.execute(
      request: const SearchEventRequestDto(
        status: ['active'],
        includeDeleted: false,
        pagination: PaginationRequestDto(page: 1, pageSize: 20),
        sortBy: 'start_at',
        sortDirection: 'asc',
      ),
    );
    final result = invocation.result;
    _isLoadingActive = false;
    if (result.ok) {
      _activeTasks = result.data!.items
          .where((event) => event.status == 'active' && event.deletedAt == null)
          .map(_toInboxTask)
          .toList(growable: false);
      _activeError = null;
    } else {
      _activeTasks = const [];
      _activeError = _errorMessage(result.error?.code, result.error?.message);
    }
    _notifyListeners();
  }

  Future<void> setCompletedExpanded(bool expanded) async {
    _isCompletedExpanded = expanded;
    if (expanded &&
        (!_hasLoadedCompleted || _completedError != null) &&
        !_isLoadingCompleted) {
      await loadCompleted();
    }
  }

  Future<void> loadCompleted() async {
    _isLoadingCompleted = true;
    _completedError = null;
    _notifyListeners();

    final invocation = await _readEventsUseCase.execute(
      request: const SearchEventRequestDto(
        status: ['completed'],
        includeDeleted: false,
        pagination: PaginationRequestDto(page: 1, pageSize: 20),
        sortBy: 'updated_at',
        sortDirection: 'desc',
      ),
    );
    final result = invocation.result;
    _isLoadingCompleted = false;
    if (result.ok) {
      final response = result.data!;
      _completedTasks = response.items
          .where(
            (event) => event.status == 'completed' && event.deletedAt == null,
          )
          .map(_toInboxTask)
          .toList(growable: false);
      _completedCount = response.pagination.total ?? _completedTasks.length;
      _hasLoadedCompleted = true;
      _completedError = null;
    } else {
      _completedError = _errorMessage(
        result.error?.code,
        result.error?.message,
      );
    }
    _notifyListeners();
  }

  Future<InboxCompletionResult> completeTask(InboxTaskViewData task) async {
    if (task.hasRecurrence) {
      return const InboxCompletionResult.failure('重复日程暂不支持完成操作');
    }
    if (_completingIds.contains(task.id)) {
      return const InboxCompletionResult.failure('该日程正在完成中');
    }

    _completingIds.add(task.id);
    _notifyListeners();
    final invocation = await _completeEventUseCase.execute(
      CompleteEventRequestDto(
        eventId: task.id,
        completedAt: DateTime.now(),
        source: 'manual',
      ),
    );
    final result = invocation.result;
    if (!result.ok) {
      _completingIds.remove(task.id);
      _notifyListeners();
      return InboxCompletionResult.failure(
        _errorMessage(result.error?.code, result.error?.message),
      );
    }

    final completedEvent = result.data!;
    if (completedEvent.status != 'completed') {
      _completingIds.remove(task.id);
      _notifyListeners();
      return const InboxCompletionResult.failure('Native 未返回 completed 状态');
    }

    final completedTask = _toInboxTask(completedEvent);
    final alreadyCached = _completedTasks.any(
      (item) => item.id == completedTask.id,
    );
    _completedTasks = [
      completedTask,
      ..._completedTasks.where((item) => item.id != completedTask.id),
    ];
    if (!alreadyCached) {
      _completedCount += 1;
    }
    _notifyListeners();

    if (_isCompletedExpanded) {
      unawaited(loadCompleted());
    }
    return const InboxCompletionResult.success();
  }

  void finalizeCompletion(String eventId) {
    _activeTasks = _activeTasks
        .where((task) => task.id != eventId)
        .toList(growable: false);
    _completingIds.remove(eventId);
    _notifyListeners();
  }

  InboxTaskViewData _toInboxTask(EventResponseDto event) {
    return InboxTaskViewData(
      id: event.id,
      title: event.title,
      dueDateLabel: _formatDueDate(event.startAt),
      importance: _mapImportance(event.importance),
      isCompleted: event.status == 'completed',
      hasRecurrence: event.hasRecurrence,
    );
  }

  TaskImportance _mapImportance(String? importance) {
    return switch (importance) {
      'important_noturgent' => TaskImportance.importantNotUrgent,
      'unimportant_urgent' => TaskImportance.unimportantUrgent,
      'important_urgent' => TaskImportance.importantUrgent,
      _ => TaskImportance.unimportantNotUrgent,
    };
  }

  String _formatDueDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  String _errorMessage(String? code, String? message) {
    if (code == null && message == null) {
      return '操作失败，请稍后重试';
    }
    return [code, message].whereType<String>().join(': ');
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

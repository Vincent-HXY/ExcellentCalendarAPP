import 'dart:async';

import '../../gateway_interfaces/search_gateway.dart';
import '../../gateway_interfaces/search_history_gateway.dart';
import '../../native_contract/search/search_request_dtos.dart';
import '../../native_contract/search/search_text_contract.dart';
import 'search_failure_message.dart';
import 'search_models.dart';

typedef SearchHistoryStateListener = void Function(SearchHistoryState state);

class SearchHistoryCoordinator {
  SearchHistoryCoordinator({
    required SearchHistoryGateway gateway,
    required this.onChanged,
    this.undoWindow = const Duration(seconds: 6),
  }) : assert(!undoWindow.isNegative),
       _gateway = gateway;

  final SearchHistoryGateway _gateway;
  final SearchHistoryStateListener onChanged;
  final Duration undoWindow;
  SearchHistoryState _state = const SearchHistoryState();
  List<String> _committed = const [];
  List<String> _desired = const [];
  int _revision = 0;
  final List<_HistoryIntent> _pendingIntents = [];
  Timer? _undoExpiry;
  bool _draining = false;
  bool _disposed = false;

  SearchHistoryState get state => _state;

  Future<void> initialize() async {
    _emit(
      _state.copyWith(
        loadPhase: SearchHistoryLoadPhase.loading,
        clearError: true,
      ),
    );
    try {
      final response = await _gateway.getLocalHistory();
      if (_disposed) return;
      _revision = response.revision;
      _committed = response.items;
      _desired = response.items;
      _pendingIntents.clear();
      _emit(
        _state.copyWith(
          loadPhase: SearchHistoryLoadPhase.ready,
          items: response.items,
          revision: response.revision,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _emit(
        _state.copyWith(
          loadPhase: SearchHistoryLoadPhase.error,
          errorMessage: searchHistoryFailureMessage(error),
        ),
      );
    }
  }

  void enterManaging() =>
      _emit(_state.copyWith(mode: SearchHistoryMode.managing));
  void exitManaging() =>
      _emit(_state.copyWith(mode: SearchHistoryMode.browsing));

  void record(String canonicalKeyword) {
    if (canonicalKeyword.isEmpty) return;
    _mutate(_HistoryIntent.record(canonicalKeyword), clearUndo: true);
  }

  void remove(String keyword) {
    _mutate(_HistoryIntent.remove(keyword), clearUndo: true);
    if (_desired.isEmpty) exitManaging();
  }

  void clear() {
    if (_desired.isEmpty) return;
    final undo = List<String>.unmodifiable(_desired);
    _mutate(const _HistoryIntent.clear(), undoItems: undo);
    if (_state.undoItems != null) _startUndoWindow();
    exitManaging();
  }

  void undoClear() {
    final undo = _state.undoItems;
    if (undo == null) return;
    _mutate(_HistoryIntent.restore(undo), clearUndo: true);
  }

  void dismissUndo() {
    if (_disposed || _state.undoItems == null) return;
    _undoExpiry?.cancel();
    _undoExpiry = null;
    _emit(_state.copyWith(clearUndo: true));
  }

  void _startUndoWindow() {
    _undoExpiry?.cancel();
    _undoExpiry = Timer(undoWindow, () {
      _undoExpiry = null;
      dismissUndo();
    });
  }

  void _mutate(
    _HistoryIntent intent, {
    List<String>? undoItems,
    bool clearUndo = false,
  }) {
    if (_disposed) return;
    final next = intent.apply(_desired);
    if (_same(_desired, next)) return;
    _pendingIntents.add(intent);
    _desired = List.unmodifiable(next);
    _emit(
      _state.copyWith(
        items: _desired,
        writePhase: SearchHistoryWritePhase.writing,
        clearError: true,
        undoItems: undoItems,
        clearUndo: clearUndo,
      ),
    );
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    var conflicts = 0;
    try {
      while (!_disposed && !_same(_committed, _desired)) {
        final submittedIntentCount = _pendingIntents.length;
        final submitted = _replay(
          _committed,
          _pendingIntents.take(submittedIntentCount),
        );
        try {
          final response = await _gateway.replaceLocalHistory(
            ReplaceSearchHistoryRequestDto(
              expectedRevision: _revision,
              items: submitted,
            ),
          );
          if (_disposed) return;
          _revision = response.revision;
          _committed = response.items;
          conflicts = 0;
          _pendingIntents.removeRange(0, submittedIntentCount);
          _desired = _replay(_committed, _pendingIntents);
          _emit(
            _state.copyWith(
              items: _desired,
              revision: _revision,
              writePhase: _same(_committed, _desired)
                  ? SearchHistoryWritePhase.idle
                  : SearchHistoryWritePhase.writing,
              clearError: true,
            ),
          );
        } on SearchGatewayFailure catch (error) {
          if (!error.isHistoryConflict || conflicts >= 2) rethrow;
          conflicts += 1;
          final latest = await _gateway.getLocalHistory();
          if (_disposed) return;
          _revision = latest.revision;
          _committed = latest.items;
          _desired = _replay(_committed, _pendingIntents);
          _emit(
            _state.copyWith(
              items: _desired,
              revision: _revision,
              clearUndo: true,
            ),
          );
        }
      }
    } catch (error) {
      if (_disposed) return;
      _desired = _committed;
      _pendingIntents.clear();
      _emit(
        _state.copyWith(
          items: _committed,
          revision: _revision,
          writePhase: SearchHistoryWritePhase.error,
          errorMessage: searchHistoryFailureMessage(error),
          clearUndo: true,
        ),
      );
    } finally {
      _draining = false;
      if (!_disposed && !_same(_committed, _desired)) unawaited(_drain());
    }
  }

  void _emit(SearchHistoryState value) {
    if (_disposed) return;
    if (value.undoItems == null) {
      _undoExpiry?.cancel();
      _undoExpiry = null;
    }
    _state = value;
    onChanged(value);
  }

  void dispose() {
    _disposed = true;
    _undoExpiry?.cancel();
    _undoExpiry = null;
  }
}

String _asciiKey(String value) {
  return SearchTextContract.analyze(value).comparisonKey;
}

List<String> _replay(List<String> committed, Iterable<_HistoryIntent> intents) {
  var result = List<String>.unmodifiable(committed);
  for (final intent in intents) {
    result = intent.apply(result);
  }
  return result;
}

enum _HistoryIntentType { record, remove, clear, restore }

class _HistoryIntent {
  const _HistoryIntent._(this.type, this.keyword, this.items);
  const _HistoryIntent.clear() : this._(_HistoryIntentType.clear, null, null);
  _HistoryIntent.record(String keyword)
    : this._(_HistoryIntentType.record, keyword, null);
  _HistoryIntent.remove(String keyword)
    : this._(_HistoryIntentType.remove, keyword, null);
  _HistoryIntent.restore(List<String> items)
    : this._(_HistoryIntentType.restore, null, List.unmodifiable(items));

  final _HistoryIntentType type;
  final String? keyword;
  final List<String>? items;

  List<String> apply(List<String> current) => switch (type) {
    _HistoryIntentType.record => <String>[
      keyword!,
      for (final item in current)
        if (_asciiKey(item) != _asciiKey(keyword!)) item,
    ].take(20).toList(growable: false),
    _HistoryIntentType.remove =>
      current
          .where((item) => _asciiKey(item) != _asciiKey(keyword!))
          .toList(growable: false),
    _HistoryIntentType.clear => const [],
    _HistoryIntentType.restore => List<String>.unmodifiable(items!),
  };
}

bool _same(List<String> first, List<String> second) {
  if (identical(first, second)) return true;
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

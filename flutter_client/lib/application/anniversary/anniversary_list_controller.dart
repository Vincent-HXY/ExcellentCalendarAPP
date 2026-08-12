import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/anniversary_gateway.dart';
import 'anniversary_models.dart';

enum AnniversaryListPhase { loading, ready, empty, error }

class AnniversaryListController extends ChangeNotifier {
  AnniversaryListController(this._gateway);

  static const int _pageSize = 20;

  final AnniversaryGateway _gateway;

  AnniversaryListPhase _phase = AnniversaryListPhase.loading;
  List<AnniversaryListItem> _items = const [];
  String? _errorMessage;
  String? _loadMoreErrorMessage;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  int _nextPage = 2;
  int _requestVersion = 0;
  bool _isDisposed = false;

  AnniversaryListPhase get phase => _phase;
  List<AnniversaryListItem> get items => _items;
  String? get errorMessage => _errorMessage;
  String? get loadMoreErrorMessage => _loadMoreErrorMessage;
  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  Future<void> initialize() => load();

  Future<void> load() async {
    final requestVersion = ++_requestVersion;
    _phase = AnniversaryListPhase.loading;
    _errorMessage = null;
    _loadMoreErrorMessage = null;
    _hasMore = false;
    _isLoadingMore = false;
    _nextPage = 2;
    _notify();

    try {
      final result = await _gateway.list(
        const AnniversaryListQuery(page: 1, pageSize: _pageSize),
      );
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _items = result.items;
      _hasMore = result.hasMore;
      _phase = result.items.isEmpty
          ? AnniversaryListPhase.empty
          : AnniversaryListPhase.ready;
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _items = const [];
      _hasMore = false;
      _phase = AnniversaryListPhase.error;
      _errorMessage = anniversaryFailureMessage(error);
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_isDisposed ||
        _phase != AnniversaryListPhase.ready ||
        !_hasMore ||
        _isLoadingMore) {
      return;
    }
    final requestVersion = _requestVersion;
    final page = _nextPage;
    _isLoadingMore = true;
    _loadMoreErrorMessage = null;
    _notify();

    try {
      final result = await _gateway.list(
        AnniversaryListQuery(page: page, pageSize: _pageSize),
      );
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      final existingIds = _items.map((item) => item.anniversary.id).toSet();
      _items = List.unmodifiable([
        ..._items,
        ...result.items.where((item) => existingIds.add(item.anniversary.id)),
      ]);
      _hasMore = result.hasMore;
      _nextPage = page + 1;
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _loadMoreErrorMessage = anniversaryFailureMessage(error);
    }
    _isLoadingMore = false;
    _notify();
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestVersion += 1;
    super.dispose();
  }
}

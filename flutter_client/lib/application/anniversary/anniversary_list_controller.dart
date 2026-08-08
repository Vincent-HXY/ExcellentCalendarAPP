import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/anniversary_gateway.dart';
import 'anniversary_models.dart';

enum AnniversaryListFilter { all, anniversary, countdown, birthday, holiday }

extension AnniversaryListFilterQuery on AnniversaryListFilter {
  AnniversaryKind? get kind {
    return switch (this) {
      AnniversaryListFilter.all => null,
      AnniversaryListFilter.anniversary => AnniversaryKind.anniversary,
      AnniversaryListFilter.countdown => AnniversaryKind.countdown,
      AnniversaryListFilter.birthday => AnniversaryKind.birthday,
      AnniversaryListFilter.holiday => AnniversaryKind.holiday,
    };
  }
}

enum AnniversaryListPhase { loading, ready, empty, error }

class AnniversaryListController extends ChangeNotifier {
  AnniversaryListController(this._gateway);

  final AnniversaryGateway _gateway;

  AnniversaryListFilter _selectedFilter = AnniversaryListFilter.all;
  AnniversaryListPhase _phase = AnniversaryListPhase.loading;
  List<AnniversaryListItem> _items = const [];
  String? _errorMessage;
  int _requestVersion = 0;
  bool _isDisposed = false;

  AnniversaryListFilter get selectedFilter => _selectedFilter;
  AnniversaryListPhase get phase => _phase;
  List<AnniversaryListItem> get items => _items;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => load();

  Future<void> load() async {
    final requestVersion = ++_requestVersion;
    _phase = AnniversaryListPhase.loading;
    _errorMessage = null;
    _notify();

    try {
      final items = await _gateway.list(
        AnniversaryListQuery(kind: _selectedFilter.kind),
      );
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _items = List.unmodifiable(items);
      _phase = items.isEmpty
          ? AnniversaryListPhase.empty
          : AnniversaryListPhase.ready;
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _items = const [];
      _phase = AnniversaryListPhase.error;
      _errorMessage = anniversaryFailureMessage(error);
    }
    _notify();
  }

  void selectFilter(AnniversaryListFilter filter) {
    if (_selectedFilter == filter) {
      return;
    }
    _selectedFilter = filter;
    unawaited(load());
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

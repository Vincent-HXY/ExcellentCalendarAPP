import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../gateway_interfaces/category_repository.dart';
import 'category_models.dart';

enum CategoryListPhase { loading, ready, empty, error }

class CategoryListController extends ChangeNotifier {
  CategoryListController(this._repository);

  final CategoryRepository _repository;
  CategoryListPhase _phase = CategoryListPhase.loading;
  List<Category> _categories = const [];
  String? _errorMessage;
  int _requestVersion = 0;
  bool _isDisposed = false;

  CategoryListPhase get phase => _phase;
  List<Category> get categories => _categories;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => load();

  Future<void> load() async {
    final requestVersion = ++_requestVersion;
    _phase = CategoryListPhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final categories = await _repository.listActiveCategories();
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _categories = sortCategories(categories);
      _phase = _categories.isEmpty
          ? CategoryListPhase.empty
          : CategoryListPhase.ready;
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _categories = const [];
      _phase = CategoryListPhase.error;
      _errorMessage = categoryFailureMessage(error);
    }
    _notify();
  }

  void addCreatedCategory(Category category) {
    final merged = <String, Category>{
      for (final existing in _categories) existing.id: existing,
      category.id: category,
    };
    _categories = sortCategories(
      merged.values.where((item) => item.deletedAt == null),
    );
    _errorMessage = null;
    _phase = _categories.isEmpty
        ? CategoryListPhase.empty
        : CategoryListPhase.ready;
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

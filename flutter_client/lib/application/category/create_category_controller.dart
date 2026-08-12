import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../gateway_interfaces/category_repository.dart';
import 'category_models.dart';

enum CreateCategoryPhase { editing, submitting }

class CreateCategoryController extends ChangeNotifier {
  CreateCategoryController(this._repository, {String initialColor = '#E58F44'})
    : _selectedColor = initialColor;

  final CategoryRepository _repository;
  CreateCategoryPhase _phase = CreateCategoryPhase.editing;
  String _name = '';
  String _description = '';
  String? _selectedColor;
  String? _nameError;
  String? _descriptionError;
  String? _submitError;
  bool _isDisposed = false;

  CreateCategoryPhase get phase => _phase;
  String get name => _name;
  String get description => _description;
  String? get selectedColor => _selectedColor;
  String? get nameError => _nameError;
  String? get descriptionError => _descriptionError;
  String? get submitError => _submitError;
  bool get isSubmitting => _phase == CreateCategoryPhase.submitting;
  bool get canSubmit =>
      _name.trim().isNotEmpty && _selectedColor != null && !isSubmitting;

  void setName(String value) {
    if (_name == value) return;
    _name = value;
    _nameError = null;
    _submitError = null;
    _notify();
  }

  void setDescription(String value) {
    if (_description == value) return;
    _description = value;
    _descriptionError = null;
    _submitError = null;
    _notify();
  }

  void selectColor(String color) {
    if (_selectedColor == color) return;
    _selectedColor = color;
    _submitError = null;
    _notify();
  }

  Future<Category?> submit() async {
    if (isSubmitting || !_validate()) {
      return null;
    }
    _phase = CreateCategoryPhase.submitting;
    _submitError = null;
    _notify();
    try {
      final category = await _repository.createCategory(
        CreateCategoryCommand(
          name: _name,
          description: _description.isEmpty ? null : _description,
          color: _selectedColor!,
        ),
      );
      return category;
    } catch (error) {
      if (error is CategoryRepositoryException &&
          error.code == CategoryFailureCode.nameEmpty) {
        _nameError = '请输入分类名称';
      } else {
        _submitError = categoryFailureMessage(error);
      }
      return null;
    } finally {
      _phase = CreateCategoryPhase.editing;
      _notify();
    }
  }

  bool _validate() {
    _nameError = null;
    _descriptionError = null;
    _submitError = null;
    if (_name.trim().isEmpty) {
      _nameError = '请输入分类名称';
    } else if (_name.runes.length > 40) {
      _nameError = '分类名称不能超过 40 个字符';
    }
    if (_description.runes.length > 200) {
      _descriptionError = '备注不能超过 200 个字符';
    }
    final color = _selectedColor;
    if (color == null || !_hexColorPattern.hasMatch(color)) {
      _submitError = '请选择有效的分类颜色';
    }
    final valid =
        _nameError == null && _descriptionError == null && _submitError == null;
    if (!valid) {
      _notify();
    }
    return valid;
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  static final RegExp _hexColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
}

import '../../application/category/category_models.dart';

/// A non-null route result means the user made an explicit choice.
///
/// A null route result is reserved for cancellation, while [category] being
/// null represents the explicit "unclassified" choice.
class CategoryPickerResult {
  const CategoryPickerResult.category(Category value) : category = value;

  const CategoryPickerResult.unclassified() : category = null;

  final Category? category;

  bool get isUnclassified => category == null;
}

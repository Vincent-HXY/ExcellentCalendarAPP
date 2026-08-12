import '../application/category/category_models.dart';

abstract interface class CategoryRepository {
  Future<List<Category>> listActiveCategories();

  Future<Category> createCategory(CreateCategoryCommand command);
}

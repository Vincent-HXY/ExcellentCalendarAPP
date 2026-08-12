class Category {
  const Category({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String? description;
  final String? color;
  final String? icon;
  final int? sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class CreateCategoryCommand {
  const CreateCategoryCommand({
    required this.name,
    required this.description,
    required this.color,
    this.icon,
    this.sortOrder,
  });

  final String name;
  final String? description;
  final String color;
  final String? icon;
  final int? sortOrder;
}

List<Category> sortCategories(Iterable<Category> categories) {
  final sorted = categories.toList(growable: false)
    ..sort((first, second) {
      final firstOrder = first.sortOrder;
      final secondOrder = second.sortOrder;
      if (firstOrder != secondOrder) {
        if (firstOrder == null) return 1;
        if (secondOrder == null) return -1;
        final sortOrderComparison = firstOrder.compareTo(secondOrder);
        if (sortOrderComparison != 0) {
          return sortOrderComparison;
        }
      }
      final createdAtComparison = first.createdAt.compareTo(second.createdAt);
      if (createdAtComparison != 0) {
        return createdAtComparison;
      }
      return first.id.compareTo(second.id);
    });
  return List<Category>.unmodifiable(sorted);
}

enum CategoryFailureCode {
  nameEmpty,
  sortOrderExhausted,
  contractValidation,
  serviceUnavailable,
  unknown,
}

class CategoryRepositoryException implements Exception {
  const CategoryRepositoryException(
    this.code, {
    this.retryable = false,
    this.debugMessage,
  });

  final CategoryFailureCode code;
  final bool retryable;
  final String? debugMessage;
}

String categoryFailureMessage(Object error) {
  if (error is! CategoryRepositoryException) {
    return '分类服务暂时不可用，请稍后重试';
  }
  return switch (error.code) {
    CategoryFailureCode.nameEmpty => '请输入分类名称',
    CategoryFailureCode.sortOrderExhausted => '分类排序空间已用尽，暂时无法创建新分类',
    CategoryFailureCode.contractValidation => '分类信息格式不正确，请检查后重试',
    CategoryFailureCode.serviceUnavailable => '分类服务暂时不可用，请稍后重试',
    CategoryFailureCode.unknown => '创建分类失败，请稍后重试',
  };
}

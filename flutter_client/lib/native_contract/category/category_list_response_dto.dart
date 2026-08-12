import '../shared/contract_value.dart';
import 'category_response_dto.dart';

class CategoryListResponseDto {
  const CategoryListResponseDto(this.items);

  final List<CategoryResponseDto> items;

  factory CategoryListResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, const {
      'items',
    }, 'CategoryListResponse');
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException(
        'CategoryListResponse.items must be an array.',
      );
    }
    final items = rawItems.indexed
        .map((entry) {
          final (index, value) = entry;
          if (value is! Map<String, dynamic>) {
            throw FormatException(
              'CategoryListResponse.items[$index] must be an object.',
            );
          }
          final category = CategoryResponseDto.fromJson(value);
          if (category.deletedAt != null) {
            throw FormatException(
              'CategoryListResponse.items[$index].deleted_at must be null.',
            );
          }
          return category;
        })
        .toList(growable: false);
    final ids = <String>{};
    for (final category in items) {
      if (!ids.add(category.id)) {
        throw const FormatException(
          'CategoryListResponse.items must not contain duplicate IDs.',
        );
      }
    }
    for (var index = 1; index < items.length; index += 1) {
      if (_compare(items[index - 1], items[index]) > 0) {
        throw const FormatException(
          'CategoryListResponse.items must use Contract order.',
        );
      }
    }
    return CategoryListResponseDto(
      List<CategoryResponseDto>.unmodifiable(items),
    );
  }

  static int _compare(CategoryResponseDto first, CategoryResponseDto second) {
    final firstOrder = first.sortOrder;
    final secondOrder = second.sortOrder;
    if (firstOrder != secondOrder) {
      if (firstOrder == null) return 1;
      if (secondOrder == null) return -1;
      final orderComparison = firstOrder.compareTo(secondOrder);
      if (orderComparison != 0) return orderComparison;
    }
    final createdAtComparison = first.createdAt.compareTo(second.createdAt);
    if (createdAtComparison != 0) return createdAtComparison;
    return first.id.compareTo(second.id);
  }
}

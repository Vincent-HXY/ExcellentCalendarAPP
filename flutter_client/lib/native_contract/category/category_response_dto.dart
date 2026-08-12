import '../shared/contract_value.dart';
import 'create_category_request_dto.dart';

class CategoryResponseDto {
  const CategoryResponseDto({
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

  factory CategoryResponseDto.fromJson(Map<String, dynamic> json) {
    const keys = {
      'id',
      'name',
      'description',
      'color',
      'icon',
      'sort_order',
      'created_at',
      'updated_at',
      'deleted_at',
    };
    ContractValue.requireExactKeys(json, keys, 'CategoryResponse');
    final id = ContractValue.nonEmptyString(json, 'id', 'CategoryResponse');
    CategoryContractValue.uuidV4(id, 'CategoryResponse.id');
    final name = ContractValue.nonEmptyString(json, 'name', 'CategoryResponse');
    CategoryContractValue.nonBlankText(
      name,
      'CategoryResponse.name',
      maximumLength: 40,
    );
    final description = ContractValue.optionalString(
      json,
      'description',
      'CategoryResponse',
    );
    CategoryContractValue.optionalNonBlankText(
      description,
      'CategoryResponse.description',
      maximumLength: 200,
    );
    final color = ContractValue.optionalString(
      json,
      'color',
      'CategoryResponse',
    );
    CategoryContractValue.optionalCanonicalColor(
      color,
      'CategoryResponse.color',
    );
    final icon = ContractValue.optionalString(json, 'icon', 'CategoryResponse');
    CategoryContractValue.optionalNonBlankText(
      icon,
      'CategoryResponse.icon',
      maximumLength: 64,
    );
    final createdAt = ContractValue.utcDateTime(
      json,
      'created_at',
      'CategoryResponse',
      wholeSecond: true,
    );
    final updatedAt = ContractValue.utcDateTime(
      json,
      'updated_at',
      'CategoryResponse',
      wholeSecond: true,
    );
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException(
        'CategoryResponse.updated_at cannot precede created_at.',
      );
    }
    return CategoryResponseDto(
      id: id,
      name: name,
      description: description,
      color: color,
      icon: icon,
      sortOrder: ContractValue.optionalInteger(
        json,
        'sort_order',
        'CategoryResponse',
        minimum: 0,
        maximum: CategoryContractValue.maximumSortOrder,
      ),
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: ContractValue.optionalUtcDateTime(
        json,
        'deleted_at',
        'CategoryResponse',
        wholeSecond: true,
      ),
    );
  }
}

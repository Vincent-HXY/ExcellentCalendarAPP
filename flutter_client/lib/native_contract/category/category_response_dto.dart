import '../shared/contract_value.dart';

class CategoryResponseDto {
  const CategoryResponseDto({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.icon,
    this.sortOrder,
    this.deletedAt,
  });

  final String id;
  final String name;
  final String? color;
  final String? icon;
  final int? sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory CategoryResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'id',
      'name',
      'created_at',
      'updated_at',
    }.union(json.keys.where((key) => {
      'color',
      'icon',
      'sort_order',
      'deleted_at',
    }.contains(key)).toSet()), 'CategoryResponse');
    return CategoryResponseDto(
      id: ContractValue.nonEmptyString(json, 'id', 'CategoryResponse'),
      name: ContractValue.nonEmptyString(json, 'name', 'CategoryResponse'),
      color: ContractValue.optionalString(json, 'color', 'CategoryResponse'),
      icon: ContractValue.optionalString(json, 'icon', 'CategoryResponse'),
      sortOrder: ContractValue.optionalInteger(
        json,
        'sort_order',
        'CategoryResponse',
        minimum: 0,
      ),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'CategoryResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'CategoryResponse',
      ),
      deletedAt: ContractValue.optionalUtcDateTime(
        json,
        'deleted_at',
        'CategoryResponse',
      ),
    );
  }
}

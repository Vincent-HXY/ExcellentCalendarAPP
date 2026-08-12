import 'category_list_response_dto.dart';
import 'category_response_dto.dart';

abstract final class CategoryMapper {
  static CategoryResponseDto category(Object? rawData) =>
      CategoryResponseDto.fromJson(_object(rawData, 'CategoryResponse'));

  static CategoryListResponseDto list(Object? rawData) =>
      CategoryListResponseDto.fromJson(
        _object(rawData, 'CategoryListResponse'),
      );

  static Map<String, dynamic> _object(Object? value, String parent) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('$parent data must be an object.');
  }
}

import '../native_contract/category/category_list_response_dto.dart';
import '../native_contract/category/category_response_dto.dart';
import '../native_contract/category/create_category_request_dto.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class CategoryNativeGateway {
  Future<NativeInvocation<CategoryListResponseDto>> listCategories();

  Future<NativeInvocation<CategoryResponseDto>> createCategory(
    CreateCategoryRequestDto request,
  );
}

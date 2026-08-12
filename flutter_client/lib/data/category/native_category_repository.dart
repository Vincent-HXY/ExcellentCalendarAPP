import '../../application/category/category_models.dart';
import '../../gateway_interfaces/category_native_gateway.dart';
import '../../gateway_interfaces/category_repository.dart';
import '../../native_contract/category/category_response_dto.dart';
import '../../native_contract/category/create_category_request_dto.dart';
import '../../native_contract/common/native_error_codes.dart';
import '../../native_contract/shared/native_invocation.dart';

class NativeCategoryRepository implements CategoryRepository {
  const NativeCategoryRepository(this._nativeGateway);

  final CategoryNativeGateway _nativeGateway;

  @override
  Future<List<Category>> listActiveCategories() async {
    final response = _unwrap(await _nativeGateway.listCategories());
    final received = response.items.map(_toCategory).toList(growable: false);
    final sorted = sortCategories(received);
    if (!_sameOrder(received, sorted)) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
        debugMessage: 'category.list returned items in a non-contract order.',
      );
    }
    return sorted;
  }

  @override
  Future<Category> createCategory(CreateCategoryCommand command) async {
    final response = _unwrap(
      await _nativeGateway.createCategory(
        CreateCategoryRequestDto(
          name: command.name,
          description: command.description,
          color: command.color,
          icon: command.icon,
          sortOrder: command.sortOrder,
        ),
      ),
    );
    final category = _toCategory(response);
    if (category.deletedAt != null || category.color == null) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
        debugMessage:
            'category.create returned a deleted or colorless Category.',
      );
    }
    return category;
  }

  T _unwrap<T>(NativeInvocation<T> invocation) {
    final result = invocation.result;
    if (result.ok && result.data != null) return result.data as T;
    final error = result.error;
    throw CategoryRepositoryException(
      _failureCode(error?.code),
      retryable: error?.retryable ?? false,
      debugMessage: error?.message,
    );
  }

  static Category _toCategory(CategoryResponseDto value) => Category(
    id: value.id,
    name: value.name,
    description: value.description,
    color: value.color,
    icon: value.icon,
    sortOrder: value.sortOrder,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    deletedAt: value.deletedAt,
  );

  static CategoryFailureCode _failureCode(String? code) => switch (code) {
    NativeErrorCodes.categoryNameEmpty => CategoryFailureCode.nameEmpty,
    NativeErrorCodes.categorySortOrderExhausted =>
      CategoryFailureCode.sortOrderExhausted,
    NativeErrorCodes.contractValidationFailed =>
      CategoryFailureCode.contractValidation,
    NativeErrorCodes.featureNotImplemented ||
    NativeErrorCodes.storageNotInitialized ||
    NativeErrorCodes.storageIoError ||
    NativeErrorCodes.storageDataCorrupted ||
    NativeErrorCodes.nativeInternalError =>
      CategoryFailureCode.serviceUnavailable,
    _ => CategoryFailureCode.unknown,
  };

  static bool _sameOrder(List<Category> first, List<Category> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      if (first[index].id != second[index].id) return false;
    }
    return true;
  }
}

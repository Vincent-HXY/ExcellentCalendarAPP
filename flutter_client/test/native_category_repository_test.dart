import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/data/category/native_category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/category_native_gateway.dart';
import 'package:excellent_calendar/native_contract/category/category_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/category/category_response_dto.dart';
import 'package:excellent_calendar/native_contract/category/create_category_request_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'NativeCategoryRepository maps typed list/create without dynamic maps',
    () async {
      final gateway = _FakeCategoryNativeGateway(
        listItems: [_response(_firstId, sortOrder: 0)],
        createResponse: _response(_secondId, sortOrder: 1),
      );
      final repository = NativeCategoryRepository(gateway);

      final listed = await repository.listActiveCategories();
      final created = await repository.createCategory(
        const CreateCategoryCommand(
          name: '  学习  ',
          description: '  课程计划  ',
          color: '#5c93e5',
        ),
      );

      expect(listed.single.id, _firstId);
      expect(created.id, _secondId);
      expect(gateway.lastCreate!.toJson(), {
        'name': '  学习  ',
        'description': '  课程计划  ',
        'color': '#5c93e5',
        'icon': null,
        'sort_order': null,
      });
    },
  );

  test(
    'non-contract list order is rejected instead of silently reinterpreted',
    () async {
      final repository = NativeCategoryRepository(
        _FakeCategoryNativeGateway(
          listItems: [
            _response(_secondId, sortOrder: 2),
            _response(_firstId, sortOrder: 1),
          ],
          createResponse: _response(_secondId, sortOrder: 2),
        ),
      );

      await expectLater(
        repository.listActiveCategories(),
        throwsA(
          isA<CategoryRepositoryException>().having(
            (error) => error.code,
            'code',
            CategoryFailureCode.contractValidation,
          ),
        ),
      );
    },
  );

  test(
    'FEATURE_NOT_IMPLEMENTED maps to service unavailable, never success',
    () async {
      final repository = NativeCategoryRepository(
        _FakeCategoryNativeGateway(
          listFailureCode: 'FEATURE_NOT_IMPLEMENTED',
          listItems: const [],
          createResponse: _response(_secondId, sortOrder: 1),
        ),
      );

      await expectLater(
        repository.listActiveCategories(),
        throwsA(
          isA<CategoryRepositoryException>().having(
            (error) => error.code,
            'code',
            CategoryFailureCode.serviceUnavailable,
          ),
        ),
      );
    },
  );

  test('sort-order exhaustion remains a typed Category failure', () async {
    final repository = NativeCategoryRepository(
      _FakeCategoryNativeGateway(
        createFailureCode: 'CATEGORY_SORT_ORDER_EXHAUSTED',
        listItems: const [],
        createResponse: _response(_secondId, sortOrder: 1),
      ),
    );

    await expectLater(
      repository.createCategory(
        const CreateCategoryCommand(
          name: '工作',
          description: null,
          color: '#39AFBD',
        ),
      ),
      throwsA(
        isA<CategoryRepositoryException>().having(
          (error) => error.code,
          'code',
          CategoryFailureCode.sortOrderExhausted,
        ),
      ),
    );
  });
}

class _FakeCategoryNativeGateway implements CategoryNativeGateway {
  _FakeCategoryNativeGateway({
    required this.listItems,
    required this.createResponse,
    this.listFailureCode,
    this.createFailureCode,
  });

  final List<CategoryResponseDto> listItems;
  final CategoryResponseDto createResponse;
  final String? listFailureCode;
  final String? createFailureCode;
  CreateCategoryRequestDto? lastCreate;

  @override
  Future<NativeInvocation<CategoryListResponseDto>> listCategories() async {
    final failureCode = listFailureCode;
    if (failureCode != null) {
      return _failureInvocation<CategoryListResponseDto>(failureCode);
    }
    return _successInvocation(CategoryListResponseDto(listItems));
  }

  @override
  Future<NativeInvocation<CategoryResponseDto>> createCategory(
    CreateCategoryRequestDto request,
  ) async {
    lastCreate = request;
    if (createFailureCode case final failureCode?) {
      return _failureInvocation<CategoryResponseDto>(failureCode);
    }
    return _successInvocation(createResponse);
  }
}

NativeInvocation<T> _successInvocation<T>(T data) => NativeInvocation<T>(
  rawResponse: const {},
  result: NativeResultDto<T>(
    ok: true,
    data: data,
    error: null,
    contractVersion: 2,
    requestId: 'category-success',
  ),
  isNativeResult: true,
);

NativeInvocation<T> _failureInvocation<T>(String code) => NativeInvocation<T>(
  rawResponse: const {},
  result: NativeResultDto<T>(
    ok: false,
    data: null,
    error: NativeErrorDto(
      code: code,
      message: 'Category is planned.',
      details: const {},
      retryable: false,
    ),
    contractVersion: 2,
    requestId: 'category-failure',
  ),
  isNativeResult: true,
);

CategoryResponseDto _response(String id, {required int sortOrder}) =>
    CategoryResponseDto(
      id: id,
      name: '分类 $sortOrder',
      description: null,
      color: '#5C93E5',
      icon: null,
      sortOrder: sortOrder,
      createdAt: DateTime.utc(2026, 8, 10, sortOrder),
      updatedAt: DateTime.utc(2026, 8, 10, sortOrder),
      deletedAt: null,
    );

const _firstId = '40000000-0000-4000-8000-000000000001';
const _secondId = '40000000-0000-4000-8000-000000000002';

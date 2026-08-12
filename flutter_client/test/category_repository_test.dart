import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/native_contract/category/category_response_dto.dart';
import 'package:excellent_calendar/native_contract/category/create_category_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeCategoryRepository', () {
    test(
      'listActiveCategories uses stable sort_order, created_at, id order',
      () async {
        final repository = FakeCategoryRepository(
          seedDefault: false,
          initialCategories: [
            _category(
              id: _categoryB,
              name: 'B',
              sortOrder: 1,
              createdAt: DateTime.utc(2026, 1, 2),
            ),
            _category(
              id: _categoryD,
              name: 'D',
              sortOrder: 1,
              createdAt: DateTime.utc(2026),
            ),
            _category(
              id: _categoryA,
              name: 'A',
              sortOrder: 0,
              createdAt: DateTime.utc(2026, 2),
            ),
            _category(
              id: _categoryC,
              name: 'C',
              sortOrder: 1,
              createdAt: DateTime.utc(2026),
            ),
            _category(
              id: _categoryE,
              name: 'E',
              sortOrder: null,
              createdAt: DateTime.utc(2025),
            ),
            _category(
              id: _categoryF,
              name: 'F',
              sortOrder: 2147483648,
              createdAt: DateTime.utc(2027),
            ),
          ],
        );

        final categories = await repository.listActiveCategories();

        expect(categories.map((item) => item.id), [
          _categoryA,
          _categoryC,
          _categoryD,
          _categoryB,
          _categoryF,
          _categoryE,
        ]);
      },
    );

    test(
      'create trims values, normalizes color, persists, and increments',
      () async {
        final repository = FakeCategoryRepository(
          clock: () => DateTime.utc(2026, 8, 9, 8, 0, 0, 987, 654),
          idGenerator: (sequence) =>
              '30000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
        );

        final first = await repository.createCategory(
          const CreateCategoryCommand(
            name: '  工作  ',
            description: '   ',
            color: '#39afbd',
          ),
        );
        final second = await repository.createCategory(
          const CreateCategoryCommand(
            name: '学习',
            description: '  专注计划  ',
            color: '#4ABD56',
          ),
        );

        expect(first.id, _createdCategory1);
        expect(first.name, '工作');
        expect(first.description, isNull);
        expect(first.color, '#39AFBD');
        expect(first.sortOrder, 1);
        expect(first.createdAt, DateTime.utc(2026, 8, 9, 8));
        expect(second.id, _createdCategory2);
        expect(second.description, '专注计划');
        expect(second.sortOrder, 2);

        final stored = await repository.listActiveCategories();
        expect(stored.map((item) => item.id), [
          FakeCategoryRepository.defaultCategoryId,
          _createdCategory1,
          _createdCategory2,
        ]);
      },
    );

    test('empty name and malformed color fail explicitly', () async {
      final repository = FakeCategoryRepository();

      expect(
        () => repository.createCategory(
          const CreateCategoryCommand(
            name: '   ',
            description: null,
            color: '#5C93E5',
          ),
        ),
        throwsA(
          isA<CategoryRepositoryException>().having(
            (error) => error.code,
            'code',
            CategoryFailureCode.nameEmpty,
          ),
        ),
      );
      expect(
        () => repository.createCategory(
          const CreateCategoryCommand(
            name: '工作',
            description: null,
            color: 'blue',
          ),
        ),
        throwsA(
          isA<CategoryRepositoryException>().having(
            (error) => error.code,
            'code',
            CategoryFailureCode.contractValidation,
          ),
        ),
      );
    });

    test(
      'automatic append fails explicitly when the safe range is full',
      () async {
        final repository = FakeCategoryRepository(
          seedDefault: false,
          initialCategories: [
            _category(
              id: _categoryA,
              name: 'Maximum',
              sortOrder: CategoryContractValue.maximumSortOrder,
              createdAt: DateTime.utc(2026),
            ),
          ],
        );

        await expectLater(
          repository.createCategory(
            const CreateCategoryCommand(
              name: 'Overflow',
              description: null,
              color: '#5C93E5',
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
      },
    );
  });

  group('existing category and Event contract DTOs', () {
    test('CategoryResponseDto parses current snake_case projection', () {
      final dto = CategoryResponseDto.fromJson({
        'id': _workCategory,
        'name': '工作',
        'description': null,
        'color': '#39AFBD',
        'icon': null,
        'sort_order': 2,
        'created_at': '2026-08-09T08:00:00Z',
        'updated_at': '2026-08-09T08:30:00Z',
        'deleted_at': null,
      });

      expect(dto.id, _workCategory);
      expect(dto.sortOrder, 2);
      expect(dto.createdAt, DateTime.utc(2026, 8, 9, 8));
      expect(dto.updatedAt, DateTime.utc(2026, 8, 9, 8, 30));
      expect(dto.deletedAt, isNull);
    });

    test('Category sort_order accepts max and rejects max plus one', () {
      final max = CategoryContractValue.maximumSortOrder;
      expect(
        const CreateCategoryRequestDto(
          name: '工作',
          description: null,
          color: '#39AFBD',
          icon: null,
          sortOrder: CategoryContractValue.maximumSortOrder,
        ).toJson()['sort_order'],
        max,
      );
      expect(
        () => CreateCategoryRequestDto(
          name: '工作',
          description: null,
          color: '#39AFBD',
          icon: null,
          sortOrder: max + 1,
        ).toJson(),
        throwsFormatException,
      );
      expect(
        () => CategoryResponseDto.fromJson({
          'id': _workCategory,
          'name': '工作',
          'description': null,
          'color': '#39AFBD',
          'icon': null,
          'sort_order': max + 1,
          'created_at': '2026-08-09T08:00:00Z',
          'updated_at': '2026-08-09T08:00:00Z',
          'deleted_at': null,
        }),
        throwsFormatException,
      );
    });

    test('Event create and search associate by category ID only', () {
      final createJson = CreateEventRequestDto.timed(
        title: '分类测试',
        startAt: DateTime.utc(2026, 8, 9, 8),
        endAt: DateTime.utc(2026, 8, 9, 9),
        timezone: 'Asia/Shanghai',
        source: 'manual',
        categoryId: 'cat_work',
      ).toJson();
      final searchJson = const SearchEventRequestDto(
        categoryIds: ['cat_work', 'cat_study'],
      ).toJson();

      expect(createJson['category_id'], 'cat_work');
      expect(createJson, isNot(contains('category_name')));
      expect(createJson, isNot(contains('type')));
      expect(searchJson['category_ids'], ['cat_work', 'cat_study']);
    });
  });
}

const _categoryA = '20000000-0000-4000-8000-000000000001';
const _categoryB = '20000000-0000-4000-8000-000000000002';
const _categoryC = '20000000-0000-4000-8000-000000000003';
const _categoryD = '20000000-0000-4000-8000-000000000004';
const _categoryE = '20000000-0000-4000-8000-000000000005';
const _categoryF = '20000000-0000-4000-8000-000000000006';
const _createdCategory1 = '30000000-0000-4000-8000-000000000001';
const _createdCategory2 = '30000000-0000-4000-8000-000000000002';
const _workCategory = '40000000-0000-4000-8000-000000000001';

Category _category({
  required String id,
  required String name,
  required int? sortOrder,
  required DateTime createdAt,
}) {
  return Category(
    id: id,
    name: name,
    description: null,
    color: '#5C93E5',
    icon: null,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: createdAt,
    deletedAt: null,
  );
}

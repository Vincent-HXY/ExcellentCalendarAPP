import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_category_adapter.dart';
import 'package:excellent_calendar/native_contract/category/create_category_request_dto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Category list/create use exact methods and snake_case payloads',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return _success(
              call.method == 'category.list'
                  ? {
                      'items': [_category()],
                    }
                  : _category(),
            );
          });
      final adapter = MethodChannelCategoryAdapter(channel: channel);

      final listed = await adapter.listCategories();
      final created = await adapter.createCategory(
        const CreateCategoryRequestDto(
          name: '  工作  ',
          description: '   ',
          color: '#39afbd',
          icon: '  briefcase  ',
          sortOrder: null,
        ),
      );

      expect(calls.map((call) => call.method), [
        'category.list',
        'category.create',
      ]);
      expect(calls.first.arguments, <String, dynamic>{});
      expect(calls.last.arguments, {
        'name': '  工作  ',
        'description': '   ',
        'color': '#39afbd',
        'icon': '  briefcase  ',
        'sort_order': null,
      });
      expect(listed.result.data!.items.single.id, _categoryId);
      expect(created.result.data!.description, '工作计划');
    },
  );

  test('native failure remains an explicit NativeResult failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => _failure('FEATURE_NOT_IMPLEMENTED'),
        );

    final invocation = await MethodChannelCategoryAdapter(
      channel: channel,
    ).listCategories();

    expect(invocation.isNativeResult, isTrue);
    expect(invocation.result.ok, isFalse);
    expect(invocation.result.error!.code, 'FEATURE_NOT_IMPLEMENTED');
  });

  test('malformed Category success becomes a local Contract failure', () async {
    final malformed = _category()..remove('description');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => _success(malformed));

    final invocation = await MethodChannelCategoryAdapter(channel: channel)
        .createCategory(
          const CreateCategoryRequestDto(
            name: '工作',
            description: null,
            color: '#39AFBD',
            icon: null,
            sortOrder: null,
          ),
        );

    expect(invocation.isNativeResult, isFalse);
    expect(invocation.result.error!.code, 'CONTRACT_VALIDATION_FAILED');
  });

  test(
    'semantic Category response violations become local Contract failures',
    () async {
      final duplicate = _category();
      final later = _category()
        ..['id'] = '40000000-0000-4000-8000-000000000002'
        ..['sort_order'] = 2;
      final earlier = _category()..['sort_order'] = 1;
      final staleUpdate = _category()..['updated_at'] = '2026-08-10T07:59:59Z';
      final cases = <({String method, Object data})>[
        (
          method: 'category.list',
          data: {
            'items': [duplicate, duplicate],
          },
        ),
        (
          method: 'category.list',
          data: {
            'items': [later, earlier],
          },
        ),
        (method: 'category.create', data: staleUpdate),
      ];

      for (final testCase in cases) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (_) async => _success(testCase.data),
            );
        final adapter = MethodChannelCategoryAdapter(channel: channel);
        final invocation = testCase.method == 'category.list'
            ? await adapter.listCategories()
            : await adapter.createCategory(
                const CreateCategoryRequestDto(
                  name: '工作',
                  description: null,
                  color: '#39AFBD',
                  icon: null,
                  sortOrder: null,
                ),
              );

        expect(invocation.isNativeResult, isFalse, reason: testCase.method);
        expect(
          invocation.result.error!.code,
          'CONTRACT_VALIDATION_FAILED',
          reason: testCase.method,
        );
      }
    },
  );
}

const _categoryId = '40000000-0000-4000-8000-000000000001';

Map<String, Object?> _category() => {
  'id': _categoryId,
  'name': '工作',
  'description': '工作计划',
  'color': '#39AFBD',
  'icon': null,
  'sort_order': 1,
  'created_at': '2026-08-10T08:00:00Z',
  'updated_at': '2026-08-10T08:00:00Z',
  'deleted_at': null,
};

Map<String, Object?> _success(Object? data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'category-test',
};

Map<String, Object?> _failure(String code) => {
  'ok': false,
  'data': null,
  'error': {
    'code': code,
    'message': 'Category is planned.',
    'details': <String, Object?>{},
    'retryable': false,
  },
  'contract_version': 2,
  'request_id': 'category-failure',
};

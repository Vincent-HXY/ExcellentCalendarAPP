import 'dart:io';

import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/data/category/native_category_repository.dart';
import 'package:excellent_calendar/main.dart' as production;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('production composition injects the system anniversary clock', () {
    final app = production.buildProductionApp();

    expect(app.anniversaryClock, isA<SystemAppClock>());
    expect(app.anniversaryClock, isNot(isA<FixedAppClock>()));
  });

  test('production source does not construct the Category fake', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, isNot(contains('FakeCategoryRepository')));
    expect(source, isNot(contains('vin_star')));
  });

  test(
    'production category composition calls native list and create',
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
      final app = production.buildProductionApp();

      expect(app.categoryRepository, isA<NativeCategoryRepository>());
      final listed = await app.categoryRepository.listActiveCategories();
      await app.categoryRepository.createCategory(
        const CreateCategoryCommand(
          name: '  工作  ',
          description: '   ',
          color: '#39afbd',
          icon: '  briefcase  ',
        ),
      );

      expect(listed.single.id, _categoryId);
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
    },
  );
}

const _categoryId = '40000000-0000-4000-8000-000000000001';

Map<String, Object?> _category() => {
  'id': _categoryId,
  'name': '工作',
  'description': null,
  'color': '#39AFBD',
  'icon': 'briefcase',
  'sort_order': 1,
  'created_at': '2026-08-11T08:00:00Z',
  'updated_at': '2026-08-11T08:00:00Z',
  'deleted_at': null,
};

Map<String, Object?> _success(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'production-category-test',
};

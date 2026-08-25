import 'package:excellent_calendar/app/routing/auth_navigator.dart';
import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/data/auth/dio_auth_gateway.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_refresh_token_secure_store.dart';
import 'package:excellent_calendar/data/category/native_category_repository.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_ring_adapter.dart';
import 'package:excellent_calendar/data/user/dio_user_gateway.dart';
import 'package:excellent_calendar/data/user/user_profile_file_cache.dart';
import 'package:excellent_calendar/main.dart' as production;
import 'package:flutter/material.dart';
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
    expect(app.ringGateway, isA<MethodChannelRingAdapter>());
  });

  test('production auth composition wires the real stack', () {
    final key = GlobalKey<NavigatorState>();
    final deps = production.buildAuthDependencies(navigatorKey: key);

    expect(deps.session, isNotNull);
    expect(deps.startupCheck, isNotNull);
    expect(deps.logoutService, isNotNull);
    expect(deps.profileCache, isA<UserProfileFileCache>());
    expect(deps.navigator, isA<NavigatorAuthNavigator>());
    // The AuthService exposes the gateways through typed interfaces; verify
    // the real dio/MethodChannel implementations are wired end to end.
    expect(deps.authService.authGateway, isA<DioAuthGateway>());
    expect(deps.authService.userGateway, isA<DioUserGateway>());
    expect(deps.secureStore, isA<MethodChannelRefreshTokenSecureStore>());
    deps.session.dispose();
  });

  test(
    'production composition always calls native Category list and create',
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
      final repository = app.categoryRepository;

      expect(repository, isA<NativeCategoryRepository>());
      final listed = await repository.listActiveCategories();
      await repository.createCategory(
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

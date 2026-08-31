import 'dart:io';

import 'package:excellent_calendar/application/anniversary/app_clock.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_appearance_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_habit_adapter.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/main.dart' as production;
import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';
import 'package:excellent_calendar/presentation/habit/habit_design.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_appearance_preferences_gateway.dart';
import 'fakes/fake_habit_gateway.dart';
import 'fakes/fake_ring_gateway.dart';
import 'fixtures/notification_fixtures.dart';
import 'fixtures/ring_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production composition injects Native adapters and no runtime Fake',
    () {
      final app = production.buildProductionApp();
      expect(app.habitGateway, isA<MethodChannelHabitAdapter>());
      expect(app.appearanceGateway, isA<MethodChannelAppearanceAdapter>());

      final productionSource = File('lib/main.dart').readAsStringSync();
      expect(productionSource, isNot(contains('FakeHabitGateway')));
      expect(
        productionSource,
        isNot(contains('FakeAppearancePreferencesGateway')),
      );
      expect(File('lib/main_habit_preview.dart').existsSync(), isFalse);
      expect(
        File('lib/data/habit/fake_habit_gateway.dart').existsSync(),
        isFalse,
      );
      expect(
        File(
          'lib/data/appearance/fake_appearance_preferences_gateway.dart',
        ).existsSync(),
        isFalse,
      );
      expect(productionSource, contains('darkTheme: buildHabitAppTheme'));
      expect(productionSource, contains('themeMode: ThemeMode.system'));
    },
  );

  test('appearance seed builds distinct semantic light and dark schemes', () {
    final seed = const Color(0xFF0F8C91);
    final light = buildHabitAppTheme(
      seedColor: seed,
      brightness: Brightness.light,
    );
    final dark = buildHabitAppTheme(
      seedColor: seed,
      brightness: Brightness.dark,
    );

    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(light.colorScheme.surface, isNot(dark.colorScheme.surface));
    expect(light.colorScheme.onSurface, isNot(dark.colorScheme.onSurface));
  });

  test(
    'appearance adapter uses the two frozen methods and strict response',
    () async {
      const channel = MethodChannel('test/appearance');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return {
              'ok': true,
              'data': {
                'habit_progress_color': call.method == 'appearance.get_local'
                    ? 'teal'
                    : (call.arguments!
                          as Map<Object?, Object?>)['habit_progress_color'],
              },
              'error': null,
              'contract_version': 2,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final adapter = MethodChannelAppearanceAdapter(channel: channel);

      expect((await adapter.getLocal()).habitProgressColor.wireValue, 'teal');
      expect(
        (await adapter.updateLocal(
          const UpdateLocalAppearanceRequestDto(
            habitProgressColor: HabitProgressColorToken.purple,
          ),
        )).habitProgressColor.wireValue,
        'purple',
      );
      expect(calls.map((call) => call.method), [
        'appearance.get_local',
        'appearance.update_local',
      ]);
      expect(calls.first.arguments, <String, dynamic>{});
    },
  );

  testWidgets('first Habit route load resolves the device timezone', (
    tester,
  ) async {
    const nativeChannel = MethodChannel('excellent_calendar/native');
    final nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'runtime.device_timezone') {
            return {
              'ok': true,
              'data': {'timezone': 'Asia/Shanghai'},
              'error': null,
              'contract_version': 2,
              'request_id': 'timezone-first-load',
            };
          }
          throw PlatformException(
            code: 'UNEXPECTED_METHOD',
            message: call.method,
          );
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, null),
    );

    final ringGateway = FakeRingGateway(
      onGetState: () async => successInvocation(ringSnapshot()),
    );
    addTearDown(ringGateway.eventController.close);

    await tester.pumpWidget(
      production.ExcellentCalendarApp(
        anniversaryClock: const SystemAppClock(),
        categoryRepository: FakeCategoryRepository(),
        ringGateway: ringGateway,
        habitGateway: FakeHabitGateway(delay: Duration.zero),
        appearanceGateway: FakeAppearancePreferencesGateway(
          delay: Duration.zero,
        ),
        initialRoute: '/habits',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      nativeCalls.map((call) => call.method),
      contains('runtime.device_timezone'),
    );
    expect(find.text('无法读取设备时区，习惯功能暂不可用'), findsNothing);
    expect(find.text('晨间阅读 📚'), findsOneWidget);
  });
}

import 'package:excellent_calendar/application/appearance/appearance_controller.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_appearance_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';
import 'package:excellent_calendar/presentation/appearance/appearance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'runtime_timezone_native_smoke_test.dart' as timezone_smoke;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Appearance channel preserves color-only settings', (
    tester,
  ) async {
    // Gradle confines integration targets to the isolated .device_test package.
    final gateway = MethodChannelAppearanceAdapter();
    final original = await gateway.getLocal();
    try {
      for (final token in HabitProgressColorToken.values) {
        final saved = await gateway.updateLocal(
          UpdateLocalAppearanceRequestDto(habitProgressColor: token),
        );
        expect(saved.toJson(), {'habit_progress_color': token.wireValue});
        final reloaded = await MethodChannelAppearanceAdapter().getLocal();
        expect(reloaded.toJson(), saved.toJson());
      }

      const channel = MethodChannel(NativeMethodChannelNames.native);
      final rejected = await channel.invokeMapMethod<String, dynamic>(
        NativeAppearanceMethods.updateLocal,
        {
          'habit_progress_color': 'blue',
          'display': {
            'font_scale_percent': 120,
            'font_weight_delta': 0,
            'font_family': 'system',
          },
        },
      );
      expect(rejected!['ok'], isFalse);
      expect((rejected['error'] as Map)['code'], 'CONTRACT_VALIDATION_FAILED');
      expect(
        (await gateway.getLocal()).habitProgressColor,
        HabitProgressColorToken.purple,
      );

      final raw = await channel.invokeMapMethod<String, dynamic>(
        NativeAppearanceMethods.getLocal,
        <String, dynamic>{},
      );
      expect(raw!['ok'], isTrue);
      expect(raw['data'], {'habit_progress_color': 'purple'});

      final controller = AppearanceController(gateway);
      try {
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(home: AppearancePage(controller: controller)),
        );
        await tester.pumpAndSettle();
        expect(find.text('习惯进度颜色'), findsOneWidget);
        expect(find.text('蓝色'), findsOneWidget);
        await tester.tap(find.text('蓝色'));
        await tester.pumpAndSettle();
        expect(
          (await gateway.getLocal()).habitProgressColor,
          HabitProgressColorToken.blue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        controller.dispose();
      }
    } finally {
      await gateway.updateLocal(
        UpdateLocalAppearanceRequestDto(
          habitProgressColor: original.habitProgressColor,
        ),
      );
    }
  });

  // Also exercise the existing complete Flutter -> Kotlin -> JNI -> C++ smoke.
  timezone_smoke.main();
}

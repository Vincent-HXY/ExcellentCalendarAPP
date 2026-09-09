import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all seven color presets round trip without typography fields', () {
    for (final token in HabitProgressColorToken.values) {
      final payload = {'habit_progress_color': token.wireValue};
      expect(
        UpdateLocalAppearanceRequestDto(habitProgressColor: token).toJson(),
        payload,
      );
      expect(LocalAppearanceResponseDto.fromJson(payload).toJson(), payload);
    }
  });

  test(
    'the frozen color-only response rejects the removed display extension',
    () {
      expect(
        () => LocalAppearanceResponseDto.fromJson({
          'habit_progress_color': 'blue',
          'display': {
            'font_scale_percent': 120,
            'font_weight_delta': 0,
            'font_family': 'system',
          },
        }),
        throwsFormatException,
      );
    },
  );

  test('missing or invalid colors remain contract failures', () {
    for (final payload in <Map<String, dynamic>>[
      {},
      {'habit_progress_color': null},
      {'habit_progress_color': '#123456'},
      {'habit_progress_color': 'blue', 'unknown': true},
    ]) {
      expect(
        () => LocalAppearanceResponseDto.fromJson(payload),
        throwsFormatException,
      );
    }
  });
}

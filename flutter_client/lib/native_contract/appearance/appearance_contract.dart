import '../shared/contract_value.dart';
import '../shared/contract_json_object.dart';
import 'display_preferences.dart';

enum HabitProgressColorToken {
  teal('teal'),
  blue('blue'),
  indigo('indigo'),
  green('green'),
  orange('orange'),
  rose('rose'),
  purple('purple');

  const HabitProgressColorToken(this.wireValue);
  final String wireValue;

  static HabitProgressColorToken fromWireValue(String value) =>
      values.where((item) => item.wireValue == value).firstOrNull ??
      (throw FormatException('Unknown Habit progress color token: $value'));
}

class LocalAppearanceResponseDto {
  const LocalAppearanceResponseDto({required this.habitProgressColor, this.display = const DisplayPreferences()});
  final HabitProgressColorToken habitProgressColor;
  final DisplayPreferences display;

  factory LocalAppearanceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractJsonObject.rejectUnknownKeys(json, const {
      'habit_progress_color',
      'display',
    }, 'LocalAppearanceResponse');
    return LocalAppearanceResponseDto(
      display: json.containsKey('display')
          ? DisplayPreferences.fromJson(json['display'] is Map<String, dynamic> ? json['display'] as Map<String, dynamic> : (throw const FormatException('display must be an object.')))
          : const DisplayPreferences(),
      habitProgressColor: HabitProgressColorToken.fromWireValue(
        ContractValue.nonEmptyString(
          json,
          'habit_progress_color',
          'LocalAppearanceResponse',
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'habit_progress_color': habitProgressColor.wireValue,
    'display': display.toJson(),
  };
}

class UpdateLocalAppearanceRequestDto {
  const UpdateLocalAppearanceRequestDto({required this.habitProgressColor, this.display});
  final HabitProgressColorToken habitProgressColor;
  final DisplayPreferences? display;
  Map<String, dynamic> toJson() => {
    'habit_progress_color': habitProgressColor.wireValue,
    if (display != null) 'display': display!.toJson(),
  };
}

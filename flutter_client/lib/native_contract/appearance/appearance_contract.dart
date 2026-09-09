import '../shared/contract_value.dart';

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
  const LocalAppearanceResponseDto({required this.habitProgressColor});
  final HabitProgressColorToken habitProgressColor;

  factory LocalAppearanceResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, const {
      'habit_progress_color',
    }, 'LocalAppearanceResponse');
    return LocalAppearanceResponseDto(
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
  };
}

class UpdateLocalAppearanceRequestDto {
  const UpdateLocalAppearanceRequestDto({required this.habitProgressColor});
  final HabitProgressColorToken habitProgressColor;
  Map<String, dynamic> toJson() => {
    'habit_progress_color': habitProgressColor.wireValue,
  };
}

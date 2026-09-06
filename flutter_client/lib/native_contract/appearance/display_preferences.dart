import '../shared/contract_value.dart';

enum DisplayFontFamily {
  system('system'),
  notoSansSc('noto_sans_sc'),
  notoSerifSc('noto_serif_sc');

  const DisplayFontFamily(this.wireValue);
  final String wireValue;
}

class DisplayPreferences {
  const DisplayPreferences({this.fontScalePercent, this.fontWeightDelta = -1, this.fontFamily = DisplayFontFamily.system});

  final int? fontScalePercent;
  final int fontWeightDelta;
  final DisplayFontFamily fontFamily;

  factory DisplayPreferences.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, const {'font_scale_percent', 'font_weight_delta', 'font_family'}, 'DisplayPreferences');
    if (!json.containsKey('font_scale_percent')) throw const FormatException('font_scale_percent is required.');
    final family = ContractValue.nonEmptyString(json, 'font_family', 'DisplayPreferences');
    return DisplayPreferences(
      fontScalePercent: ContractValue.optionalInteger(json, 'font_scale_percent', 'DisplayPreferences', minimum: 80, maximum: 150),
      fontWeightDelta: ContractValue.integer(json, 'font_weight_delta', 'DisplayPreferences', minimum: -1, maximum: 2),
      fontFamily: DisplayFontFamily.values.where((item) => item.wireValue == family).firstOrNull ?? (throw const FormatException('Unknown display font family.')),
    );
  }

  Map<String, dynamic> toJson() {
    if (fontScalePercent != null && (fontScalePercent! < 80 || fontScalePercent! > 150) || fontWeightDelta < -1 || fontWeightDelta > 2) {
      throw const FormatException('Invalid typography settings.');
    }
    return {'font_scale_percent': fontScalePercent, 'font_weight_delta': fontWeightDelta, 'font_family': fontFamily.wireValue};
  }

  @override
  bool operator ==(Object other) => other is DisplayPreferences && fontScalePercent == other.fontScalePercent && fontWeightDelta == other.fontWeightDelta && fontFamily == other.fontFamily;
  @override
  int get hashCode => Object.hash(fontScalePercent, fontWeightDelta, fontFamily);
}

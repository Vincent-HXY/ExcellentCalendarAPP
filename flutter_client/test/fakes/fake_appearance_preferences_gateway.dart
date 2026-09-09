import 'package:excellent_calendar/gateway_interfaces/appearance_preferences_gateway.dart';
import 'package:excellent_calendar/native_contract/appearance/appearance_contract.dart';

class FakeAppearancePreferencesGateway implements AppearancePreferencesGateway {
  FakeAppearancePreferencesGateway({
    this.delay = const Duration(milliseconds: 100),
    HabitProgressColorToken initial = HabitProgressColorToken.teal,
  }) : _value = initial;
  final Duration delay;
  HabitProgressColorToken _value;
  Object? nextFailure;

  @override
  Future<LocalAppearanceResponseDto> getLocal() async {
    await _wait();
    return LocalAppearanceResponseDto(habitProgressColor: _value);
  }

  @override
  Future<LocalAppearanceResponseDto> updateLocal(
    UpdateLocalAppearanceRequestDto request,
  ) async {
    await _wait();
    _value = request.habitProgressColor;
    return LocalAppearanceResponseDto(habitProgressColor: _value);
  }

  Future<void> _wait() async {
    if (delay != Duration.zero) {
      await Future<void>.delayed(delay);
    }
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
  }
}

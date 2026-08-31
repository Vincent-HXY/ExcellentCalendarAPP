import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/appearance_preferences_gateway.dart';
import '../../native_contract/appearance/appearance_contract.dart';

enum AppearancePhase { loading, ready, updating, error }

class AppearanceController extends ChangeNotifier {
  AppearanceController(this._gateway);
  final AppearancePreferencesGateway _gateway;
  AppearancePhase _phase = AppearancePhase.loading;
  HabitProgressColorToken? _token;
  String? _errorMessage;
  int _generation = 0;
  bool _disposed = false;

  AppearancePhase get phase => _phase;
  HabitProgressColorToken? get token => _token;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => load();

  Future<void> load() async {
    final generation = ++_generation;
    _phase = AppearancePhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final response = await _gateway.getLocal();
      if (_disposed || generation != _generation) return;
      _token = response.habitProgressColor;
      _phase = AppearancePhase.ready;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _phase = AppearancePhase.error;
      _errorMessage = _message(error);
    }
    _notify();
  }

  Future<bool> update(HabitProgressColorToken value) async {
    if (_phase == AppearancePhase.updating || value == _token) return false;
    final previous = _token;
    _phase = AppearancePhase.updating;
    _errorMessage = null;
    _notify();
    try {
      final response = await _gateway.updateLocal(
        UpdateLocalAppearanceRequestDto(habitProgressColor: value),
      );
      if (_disposed) return false;
      _token = response.habitProgressColor;
      _phase = AppearancePhase.ready;
      _notify();
      return true;
    } catch (error) {
      if (_disposed) return false;
      _token = previous;
      _phase = previous == null ? AppearancePhase.error : AppearancePhase.ready;
      _errorMessage = _message(error);
      _notify();
      return false;
    }
  }

  String _message(Object error) {
    if (error is AppearanceGatewayFailure) {
      return switch (error.code) {
        'APPEARANCE_COLOR_TOKEN_INVALID' ||
        'CONTRACT_VALIDATION_FAILED' ||
        'CONTRACT_VERSION_UNSUPPORTED' => '外观数据协议不兼容，请更新应用',
        'APPEARANCE_STORAGE_FAILED' => '颜色偏好保存失败，请重试',
        _ => error.message,
      };
    }
    return '外观设置加载失败';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}

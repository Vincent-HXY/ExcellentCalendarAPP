import '../native_contract/appearance/appearance_contract.dart';

abstract interface class AppearancePreferencesGateway {
  Future<LocalAppearanceResponseDto> getLocal();
  Future<LocalAppearanceResponseDto> updateLocal(
    UpdateLocalAppearanceRequestDto request,
  );
}

class AppearanceGatewayFailure implements Exception {
  const AppearanceGatewayFailure({
    required this.code,
    required this.message,
    required this.retryable,
  });
  final String code;
  final String message;
  final bool retryable;
}

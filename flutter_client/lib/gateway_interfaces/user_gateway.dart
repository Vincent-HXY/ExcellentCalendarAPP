import '../native_contract/user/current_user_response_dto.dart';
import '../native_contract/user/update_current_user_request_dto.dart';

/// Typed business gateway for the authenticated user's profile endpoints.
abstract interface class UserGateway {
  Future<CurrentUserResponseDto> getCurrentUser();

  Future<CurrentUserResponseDto> updateCurrentUser(
    UpdateCurrentUserRequestDto request,
  );

  Future<CurrentUserResponseDto> deleteAvatar();
}

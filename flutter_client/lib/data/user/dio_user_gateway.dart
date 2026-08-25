import '../../boundary_adapters/backend_api/backend_api_endpoints.dart';
import '../../boundary_adapters/backend_api/dio_backend_api_client.dart';
import '../../gateway_interfaces/user_gateway.dart';
import '../../native_contract/user/current_user_response_dto.dart';
import '../../native_contract/user/update_current_user_request_dto.dart';
import '../../native_contract/shared/native_json_normalizer.dart';

/// UserGateway implementation over the unified dio API client.
class DioUserGateway implements UserGateway {
  const DioUserGateway(this._client);

  final DioBackendApiClient _client;

  CurrentUserResponseDto _parseUser(Object? raw) =>
      CurrentUserResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  @override
  Future<CurrentUserResponseDto> getCurrentUser() {
    return _client.send<CurrentUserResponseDto>(
      endpoint: BackendApiEndpoints.userGetCurrent,
      parseData: _parseUser,
    );
  }

  @override
  Future<CurrentUserResponseDto> updateCurrentUser(
    UpdateCurrentUserRequestDto request,
  ) {
    return _client.send<CurrentUserResponseDto>(
      endpoint: BackendApiEndpoints.userUpdateCurrent,
      data: request.toJson(),
      parseData: _parseUser,
    );
  }

  @override
  Future<CurrentUserResponseDto> deleteAvatar() {
    return _client.send<CurrentUserResponseDto>(
      endpoint: BackendApiEndpoints.avatarDelete,
      parseData: _parseUser,
    );
  }
}

import 'package:excellent_calendar/gateway_interfaces/user_gateway.dart';
import 'package:excellent_calendar/native_contract/user/current_user_response_dto.dart';
import 'package:excellent_calendar/native_contract/user/update_current_user_request_dto.dart';

class FakeUserGateway implements UserGateway {
  Object? Function()? onGetCurrentUser;
  Object? Function(UpdateCurrentUserRequestDto)? onUpdateCurrentUser;
  Object? Function()? onDeleteAvatar;

  int getCurrentCalls = 0;

  Never _throwResult(Object? result) {
    if (result is Exception) throw result;
    throw StateError('FakeUserGateway result must be set.');
  }

  @override
  Future<CurrentUserResponseDto> getCurrentUser() async {
    getCurrentCalls += 1;
    final result = onGetCurrentUser?.call();
    if (result is CurrentUserResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<CurrentUserResponseDto> updateCurrentUser(
    UpdateCurrentUserRequestDto request,
  ) async {
    final result = onUpdateCurrentUser?.call(request);
    if (result is CurrentUserResponseDto) return result;
    _throwResult(result);
  }

  @override
  Future<CurrentUserResponseDto> deleteAvatar() async {
    final result = onDeleteAvatar?.call();
    if (result is CurrentUserResponseDto) return result;
    _throwResult(result);
  }
}

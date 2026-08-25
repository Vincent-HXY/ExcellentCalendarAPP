import 'package:excellent_calendar/data/user/user_profile_file_cache.dart';
import 'package:excellent_calendar/native_contract/user/cached_current_user_dto.dart';
import 'package:excellent_calendar/native_contract/user/current_user_response_dto.dart';

class FakeProfileCache implements UserProfileCacheStore {
  CachedCurrentUserDto? cached;
  int readCalls = 0;
  int writeCalls = 0;
  int clearCalls = 0;

  @override
  Future<CachedCurrentUserDto?> read() async {
    readCalls += 1;
    return cached;
  }

  @override
  Future<void> write(CurrentUserResponseDto user, DateTime cachedAt) async {
    writeCalls += 1;
    cached = CachedCurrentUserDto(currentUser: user, cachedAt: cachedAt);
  }

  @override
  Future<void> clear() async {
    clearCalls += 1;
    cached = null;
  }
}

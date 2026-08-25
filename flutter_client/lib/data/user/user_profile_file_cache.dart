import 'dart:convert';
import 'dart:io';

import '../../native_contract/user/cached_current_user_dto.dart';
import '../../native_contract/user/current_user_response_dto.dart';

/// Ordinary local cache for the public current-user aggregate.
///
/// Format: cached_current_user.schema.json v1. A corrupted or unreadable
/// cache is treated as "no cache" and never crashes the app.
abstract interface class UserProfileCacheStore {
  Future<CachedCurrentUserDto?> read();

  Future<void> write(CurrentUserResponseDto user, DateTime cachedAt);

  Future<void> clear();
}

class UserProfileFileCache implements UserProfileCacheStore {
  UserProfileFileCache({Future<File> Function()? fileProvider})
    : _fileProvider = fileProvider ?? defaultFileProvider;

  final Future<File> Function() _fileProvider;

  /// Default location: the app's ordinary cache directory. The OS may clear
  /// it, which only means the profile re-fetches — acceptable for a cache.
  static Future<File> defaultFileProvider() async {
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}excellent_calendar',
    );
    await directory.create(recursive: true);
    return File(
      '${directory.path}${Platform.pathSeparator}cached_current_user_v1.json',
    );
  }

  @override
  Future<CachedCurrentUserDto?> read() async {
    final file = await _fileProvider();
    try {
      if (!await file.exists()) {
        return null;
      }
      final text = await file.readAsString();
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      return CachedCurrentUserDto.fromJson(json);
    } catch (_) {
      // Corrupted or unreadable cache behaves like no cache.
      return null;
    }
  }

  @override
  Future<void> write(CurrentUserResponseDto user, DateTime cachedAt) async {
    final file = await _fileProvider();
    await file.parent.create(recursive: true);
    final cache = CachedCurrentUserDto(currentUser: user, cachedAt: cachedAt);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(cache.toJson()), flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _fileProvider();
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Cache cleanup is best-effort.
    }
  }
}

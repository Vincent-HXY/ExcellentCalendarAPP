import 'package:flutter/foundation.dart' show kDebugMode;

import '../../native_contract/user/current_user_response_dto.dart';
import '../../native_contract/user/user_account_response_dto.dart';
import '../../native_contract/user/user_preferences_response_dto.dart';
import '../../native_contract/user/user_profile_response_dto.dart';
import '../../native_contract/user/user_settings_dto.dart';

/// Debug-only credentials for entering the local frontend without a backend.
abstract final class LocalTestAccount {
  static const bool enabled = kDebugMode;
  static const String email = 'admin@admin.com';
  static const String password = 'admin';

  static const String _userId = '00000000-0000-4000-8000-000000000001';
  static const String accessToken =
      'local-debug-access-token-never-sent-for-login';

  static bool matches({required String email, required String password}) {
    return enabled &&
        email.trim() == LocalTestAccount.email &&
        password == LocalTestAccount.password;
  }

  static CurrentUserResponseDto createCurrentUser() {
    final createdAt = DateTime.utc(2026, 8, 27);
    return CurrentUserResponseDto(
      account: UserAccountResponseDto(
        id: _userId,
        email: email,
        status: 'active',
        emailVerifiedAt: createdAt,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      profile: UserProfileResponseDto(
        userId: _userId,
        username: 'admin',
        displayName: '本地测试管理员',
        avatar: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      preferences: UserPreferencesResponseDto(
        userId: _userId,
        locale: 'zh-CN',
        timezone: 'Asia/Shanghai',
        defaultReminderMethods: const ['popup'],
        settings: const UserSettingsDto({'theme': 'system'}),
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );
  }
}

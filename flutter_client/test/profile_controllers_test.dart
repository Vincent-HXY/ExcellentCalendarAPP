import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/user/account_security_controller.dart';
import 'package:excellent_calendar/application/user/change_email_controller.dart';
import 'package:excellent_calendar/application/user/edit_profile_controller.dart';
import 'package:excellent_calendar/application/user/profile_controller.dart';
import 'package:excellent_calendar/application/auth/logout_service.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
import 'package:excellent_calendar/native_contract/user/cached_current_user_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_profile_cache.dart';
import 'fakes/fake_refresh_token_store.dart';
import 'fakes/fake_user_gateway.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeAuthGateway authGateway;
  late FakeUserGateway userGateway;
  late FakeRefreshTokenStore store;
  late FakeProfileCache cache;
  late AuthSessionController session;
  late AuthService authService;
  late LogoutService logoutService;

  setUp(() {
    authGateway = FakeAuthGateway();
    userGateway = FakeUserGateway();
    store = FakeRefreshTokenStore();
    cache = FakeProfileCache();
    session = AuthSessionController();
    authService = AuthService(
      authGateway: authGateway,
      userGateway: userGateway,
      secureStore: store,
      session: session,
      profileCache: cache,
    );
    logoutService = LogoutService(
      authGateway: authGateway,
      secureStore: store,
      authService: authService,
    );
  });

  group('ProfileController', () {
    test('cache-first shows stale then ready after refresh', () async {
      cache.cached = CachedCurrentUserDto(
        currentUser: userDto(),
        cachedAt: DateTime.utc(2026, 8, 1),
      );
      userGateway.onGetCurrentUser = () => userDto();
      final controller = ProfileController(
        authService: authService,
        session: session,
        profileCache: cache,
      );
      await controller.load();
      expect(controller.phase, ProfileLoadPhase.ready);
      expect(controller.user!.account.email, 'user@example.com');
      expect(cache.writeCalls, 1);
    });

    test(
      'refresh failure without cache shows the full error state with retry',
      () async {
        userGateway.onGetCurrentUser = () =>
            throw const BackendTransportException(BackendTransportKind.timeout);
        final controller = ProfileController(
          authService: authService,
          session: session,
          profileCache: cache,
        );
        await controller.load();
        expect(controller.phase, ProfileLoadPhase.error);
        expect(controller.errorMessage, '请求超时，请检查网络后重试');
      },
    );

    test('refresh failure with cache shows stale state', () async {
      cache.cached = CachedCurrentUserDto(
        currentUser: userDto(),
        cachedAt: DateTime.utc(2026, 8, 1),
      );
      userGateway.onGetCurrentUser = () =>
          throw const BackendTransportException(BackendTransportKind.network);
      final controller = ProfileController(
        authService: authService,
        session: session,
        profileCache: cache,
      );
      await controller.load();
      expect(controller.phase, ProfileLoadPhase.stale);
      expect(controller.user, isNotNull);
    });

    test('deleteAvatar applies the server response', () async {
      session.updateCurrentUser(userDto());
      final withoutAvatar = userDto();
      userGateway.onDeleteAvatar = () => withoutAvatar;
      userGateway.onGetCurrentUser = () => withoutAvatar;
      final controller = ProfileController(
        authService: authService,
        session: session,
        profileCache: cache,
      );
      final outcome = await controller.deleteAvatar();
      expect(outcome, ProfileActionOutcome.deletedAvatar);
      expect(session.currentUser!.profile.avatar, isNull);
    });
  });

  group('EditProfileController', () {
    test('save is disabled without changes and re-enabled after an edit', () {
      final controller = EditProfileController(
        authService,
        initialUser: userDto(),
      );
      expect(controller.canSave, isFalse);
      controller.setDisplayName('New Name');
      expect(controller.canSave, isTrue);
    });

    test('save sends changed fields and refreshes the user', () async {
      var captured = 0;
      userGateway.onUpdateCurrentUser = (request) {
        captured += 1;
        expect(request.toJson(), {
          'username': 'calendar_user',
          'display_name': 'New Name',
          'locale': 'zh-CN',
          'timezone': 'Asia/Shanghai',
        });
        return userDto();
      };
      userGateway.onGetCurrentUser = () => userDto();
      final controller = EditProfileController(
        authService,
        initialUser: userDto(),
      );
      controller.setDisplayName('New Name');
      final outcome = await controller.submit();
      expect(outcome, EditProfileOutcome.saved);
      expect(captured, 1);
    });

    test('username conflict keeps the input and marks the field', () async {
      userGateway.onUpdateCurrentUser = (_) => throw BackendApiException(
        error: apiErrorDto('AUTH_USERNAME_ALREADY_EXISTS'),
        requestId: 'r1',
      );
      final controller = EditProfileController(
        authService,
        initialUser: userDto(),
      );
      controller.setUsername('taken_name');
      await controller.submit();
      expect(controller.usernameError, '该用户名已被使用');
      expect(controller.username, 'taken_name');
    });
  });

  group('ChangeEmailController', () {
    test('success returns the email change challenge', () async {
      var key = '';
      authGateway.onEmailChangeRequest =
          (request, {required idempotencyKey}) async {
            key = idempotencyKey;
            expect(request.newEmail, 'new@example.com');
            expect(request.currentPassword, 'current-pass');
            return challengeDto(
              purpose: 'email_change',
              actionId: '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
            );
          };
      final controller = ChangeEmailController(
        authService,
        initialUser: userDto(),
      );
      controller.setNewEmail('new@example.com');
      controller.setCurrentPassword('current-pass');
      final outcome = await controller.submit();
      expect(outcome, ChangeEmailOutcome.requested);
      expect(
        controller.challenge!.actionId,
        '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
      );
      expect(key, isNotEmpty);
    });

    test('wrong password marks the field and clears it', () async {
      authGateway.onEmailChangeRequest = (_, {required idempotencyKey}) =>
          throw BackendApiException(
            error: apiErrorDto('AUTH_CURRENT_PASSWORD_INVALID'),
            requestId: 'r1',
          );
      final controller = ChangeEmailController(
        authService,
        initialUser: userDto(),
      );
      controller.setNewEmail('new@example.com');
      controller.setCurrentPassword('wrong-pass');
      await controller.submit();
      expect(controller.currentPasswordError, '当前密码不正确');
      expect(controller.currentPassword, '');
    });
  });

  group('AccountSecurityController', () {
    test('logout completes local cleanup and reports loggedOut', () async {
      store.record = SecureRefreshTokenRecordResponseDto(
        refreshToken: refreshToken,
        sessionId: sessionId,
        expiresAt: DateTime.utc(2026, 8, 31),
      );
      session.markAuthenticated(
        accessToken: accessToken,
        currentUser: userDto(),
      );
      final controller = AccountSecurityController(logoutService);
      expect(await controller.logout(), AccountSecurityOutcome.loggedOut);
      expect(session.status, AuthStatus.unauthenticated);
      expect(store.record, isNull);
    });

    test('logoutAll revokes every device and clears locally', () async {
      session.markAuthenticated(
        accessToken: accessToken,
        currentUser: userDto(),
      );
      final controller = AccountSecurityController(logoutService);
      expect(await controller.logoutAll(), AccountSecurityOutcome.loggedOut);
      expect(authGateway.logoutAllCalls, 1);
      expect(session.status, AuthStatus.unauthenticated);
    });
  });
}

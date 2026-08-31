import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/logout_service.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/user/current_user_response_dto.dart';
import 'package:excellent_calendar/presentation/profile/pages/account_security_page.dart';
import 'package:excellent_calendar/presentation/profile/pages/edit_profile_page.dart';
import 'package:excellent_calendar/presentation/profile/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_auth_gateway.dart';
import 'fakes/fake_navigator.dart';
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
  late FakeAuthNavigator navigator;

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
    navigator = FakeAuthNavigator();
    userGateway.onGetCurrentUser = () => userDto();
  });

  group('ProfilePage', () {
    testWidgets('renders the user rows after load', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            authService: authService,
            session: session,
            navigator: navigator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Calendar User'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.text('已验证'), findsOneWidget);
    });

    testWidgets('avatar change shows the unsupported notice', (tester) async {
      session.updateCurrentUser(userDto());
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            authService: authService,
            session: session,
            navigator: navigator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('更换头像'));
      await tester.pump();
      expect(find.text('头像修改功能暂不支持'), findsOneWidget);
    });

    testWidgets('avatar delete asks for confirmation and applies the result', (
      tester,
    ) async {
      var deleted = 0;
      session.updateCurrentUser(userWithAvatar());
      // 删除后服务端返回无头像的资料，刷新必须以此为准。
      userGateway.onGetCurrentUser = () =>
          deleted == 0 ? userWithAvatar() : userDto();
      userGateway.onDeleteAvatar = () {
        deleted += 1;
        return userDto();
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            authService: authService,
            session: session,
            navigator: navigator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('删除头像'));
      await tester.pumpAndSettle();
      expect(find.text('确定要删除当前头像吗？删除后将恢复默认头像。'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pump();
      await tester.pump();
      expect(deleted, 1);
      expect(session.currentUser!.profile.avatar, isNull);
    });

    testWidgets('failure without cache shows error state with retry', (
      tester,
    ) async {
      userGateway.onGetCurrentUser = () =>
          throw const BackendTransportException(BackendTransportKind.network);
      await tester.pumpWidget(
        MaterialApp(
          home: ProfilePage(
            authService: authService,
            session: session,
            navigator: navigator,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('重试'), findsOneWidget);
      userGateway.onGetCurrentUser = () => userDto();
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Calendar User'), findsOneWidget);
    });

    testWidgets(
      'local appearance remains reachable when remote profile fails',
      (tester) async {
        var opened = false;
        userGateway.onGetCurrentUser = () =>
            throw const BackendTransportException(BackendTransportKind.network);
        await tester.pumpWidget(
          MaterialApp(
            home: ProfilePage(
              authService: authService,
              session: session,
              navigator: navigator,
              onOpenAppearance: () => opened = true,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.text('外观设置（保存在本机）'));
        expect(opened, isTrue);
      },
    );
  });

  group('EditProfilePage', () {
    testWidgets('save stays disabled until a change is made', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EditProfilePage(
            authService: authService,
            initialUser: userDto(),
          ),
        ),
      );
      final button = tester.widget<FilledButton>(
        find.ancestor(of: find.text('保存'), matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
      await tester.enterText(find.byType(TextField).at(0), 'New Name');
      await tester.pump();
      final enabled = tester.widget<FilledButton>(
        find.ancestor(of: find.text('保存'), matching: find.byType(FilledButton)),
      );
      expect(enabled.onPressed, isNotNull);
    });
  });

  group('AccountSecurityPage', () {
    testWidgets('logout asks for confirmation and returns to login', (
      tester,
    ) async {
      session.markAuthenticated(
        accessToken: accessToken,
        currentUser: userDto(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSecurityPage(
            logoutService: logoutService,
            navigator: navigator,
          ),
        ),
      );
      await tester.tap(find.text('退出当前设备'));
      await tester.pumpAndSettle();
      expect(find.text('确定要退出当前设备吗？'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pump();
      await tester.pump();
      expect(navigator.goToLoginCalls, 1);
      expect(session.status, AuthStatus.unauthenticated);
    });

    testWidgets('cancel leaves the session untouched', (tester) async {
      session.markAuthenticated(
        accessToken: accessToken,
        currentUser: userDto(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AccountSecurityPage(
            logoutService: logoutService,
            navigator: navigator,
          ),
        ),
      );
      await tester.tap(find.text('退出所有设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(session.status, AuthStatus.authenticated);
      expect(navigator.goToLoginCalls, 0);
    });
  });
}

Map<String, Object?> userWithAvatarJson() {
  final json = userJson();
  final profile = Map<String, Object?>.from(json['profile'] as Map);
  profile['avatar'] = {
    'asset_id': 'ad2169d0-d6da-48f1-9952-f94d952231b8',
    'url': 'https://cdn.example.com/avatar/ad2169d0',
    'thumbnail_url': 'https://cdn.example.com/avatar/ad2169d0/thumb',
    'etag': 'avatar-v1',
    'updated_at': '2026-08-01T02:00:00Z',
  };
  json['profile'] = profile;
  return json;
}

CurrentUserResponseDto userWithAvatar() =>
    CurrentUserResponseDto.fromJson(userWithAvatarJson());

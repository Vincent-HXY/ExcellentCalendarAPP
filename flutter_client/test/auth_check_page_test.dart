import 'package:excellent_calendar/application/auth/auth_service.dart';
import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:excellent_calendar/application/auth/startup_auth_check_use_case.dart';
import 'package:excellent_calendar/application/auth/token_refresh_coordinator.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/secure_refresh_token_record_response_dto.dart';
import 'package:excellent_calendar/presentation/auth/pages/auth_check_page.dart';
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
  late AuthSessionController session;
  late FakeAuthNavigator navigator;

  StartupAuthCheckUseCase useCase() {
    final coordinator = TokenRefreshCoordinator(
      authGateway: authGateway,
      secureStore: store,
      session: session,
    );
    final authService = AuthService(
      authGateway: authGateway,
      userGateway: userGateway,
      secureStore: store,
      session: session,
      profileCache: FakeProfileCache(),
    );
    return StartupAuthCheckUseCase(
      secureStore: store,
      refreshCoordinator: coordinator,
      session: session,
      authService: authService,
    );
  }

  setUp(() {
    authGateway = FakeAuthGateway();
    userGateway = FakeUserGateway();
    store = FakeRefreshTokenStore();
    session = AuthSessionController();
    navigator = FakeAuthNavigator();
  });

  testWidgets('no stored token routes to login', (tester) async {
    store.record = null;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthCheckPage(startupCheck: useCase(), navigator: navigator),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(navigator.goToLoginCalls, 1);
  });

  testWidgets('valid stored token routes home', (tester) async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    authGateway.onRefreshSession = (_) => tokenPairDto();
    userGateway.onGetCurrentUser = () => userDto();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthCheckPage(startupCheck: useCase(), navigator: navigator),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(navigator.goToHomeCalls, 1);
    expect(session.status, AuthStatus.authenticated);
  });

  testWidgets('rejected token routes to login', (tester) async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    authGateway.onRefreshSession = (_) => throw BackendApiException(
      error: apiErrorDto('AUTH_REFRESH_TOKEN_REUSED'),
      requestId: 'r1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AuthCheckPage(startupCheck: useCase(), navigator: navigator),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(navigator.goToLoginCalls, 1);
  });

  testWidgets('network failure shows recovery state and retry recovers', (
    tester,
  ) async {
    store.record = SecureRefreshTokenRecordResponseDto(
      refreshToken: 'old-refresh-token-value-at-least-32-chars',
      sessionId: sessionId,
      expiresAt: DateTime.utc(2026, 8, 31),
    );
    var offline = true;
    authGateway.onRefreshSession = (_) {
      if (offline) {
        throw const BackendTransportException(BackendTransportKind.network);
      }
      return tokenPairDto();
    };
    userGateway.onGetCurrentUser = () => userDto();
    await tester.pumpWidget(
      MaterialApp(
        home: AuthCheckPage(startupCheck: useCase(), navigator: navigator),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('登录状态恢复失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    offline = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump();
    expect(navigator.goToHomeCalls, 1);
  });
}

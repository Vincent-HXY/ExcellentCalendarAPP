import 'package:excellent_calendar/application/auth/auth_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/backend_api_fixtures.dart';

void main() {
  late AuthSessionController session;

  setUp(() {
    session = AuthSessionController();
  });

  test('session-ending transitions bump the generation', () {
    final initial = session.generation;
    session.markAuthenticated(accessToken: accessToken, currentUser: userDto());
    expect(session.generation, initial + 1);

    session.clearSilently();
    expect(session.generation, initial + 2);

    session.markUnauthenticated();
    expect(session.generation, initial + 3);
  });

  test('same-session updates keep the generation stable', () {
    session.markAuthenticated(accessToken: accessToken, currentUser: userDto());
    final generation = session.generation;

    session.updateAccessToken('rotated-access-token-value-32-chars');
    session.updateCurrentUser(userDto());
    expect(session.generation, generation);
    expect(session.status, AuthStatus.authenticated);
  });
}

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../native_contract/user/current_user_response_dto.dart';

/// Authentication state machine for the in-memory session.
enum AuthStatus { unknown, unauthenticated, authenticated }

/// Holds the session's in-memory facts only.
///
/// The Access Token lives here and is never persisted. The Refresh Token is
/// never kept here at all; it only passes between the Backend and the Android
/// Keystore for the duration of a single request.
class AuthSessionController extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  String? _accessToken;
  CurrentUserResponseDto? _currentUser;
  bool _disposed = false;

  /// Monotonic session epoch: bumped whenever a logical session ends or a new
  /// one starts. In-flight async flows capture it and must discard their
  /// results when it no longer matches (e.g. logout during a refresh).
  int _generation = 0;

  AuthStatus get status => _status;
  String? get accessToken => _accessToken;
  CurrentUserResponseDto? get currentUser => _currentUser;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  int get generation => _generation;

  void markAuthenticated({
    required String accessToken,
    CurrentUserResponseDto? currentUser,
  }) {
    _generation += 1;
    _status = AuthStatus.authenticated;
    _accessToken = accessToken;
    if (currentUser != null) {
      _currentUser = currentUser;
    }
    _notify();
  }

  void markUnauthenticated() {
    _generation += 1;
    _status = AuthStatus.unauthenticated;
    _accessToken = null;
    _currentUser = null;
    _notify();
  }

  /// Updates only the Access Token after a refresh. Same logical session, so
  /// the generation is deliberately unchanged.
  void updateAccessToken(String accessToken) {
    _status = AuthStatus.authenticated;
    _accessToken = accessToken;
    _notify();
  }

  /// Updates the in-memory user aggregate. Same logical session, so the
  /// generation is deliberately unchanged.
  void updateCurrentUser(CurrentUserResponseDto currentUser) {
    _currentUser = currentUser;
    _notify();
  }

  /// Clears all session facts without notifying (used during teardown or
  /// before navigation replaces the whole UI). Bumps the generation so any
  /// in-flight refresh discards its result instead of reviving the session.
  void clearSilently() {
    _generation += 1;
    _status = AuthStatus.unauthenticated;
    _accessToken = null;
    _currentUser = null;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

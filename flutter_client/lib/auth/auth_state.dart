/// Authentication status, using a single enum (not multiple booleans).
enum AuthStatus {
  /// App just launched, no decision yet.
  initial,

  /// Checking whether a Refresh Token exists in Android secure storage.
  checking,

  /// Attempting to refresh the session with a stored Refresh Token.
  refreshing,

  /// User is authenticated and has a valid Access Token.
  authenticated,

  /// No valid session exists; user must log in.
  unauthenticated,

  /// Network is unavailable and we cannot determine auth state.
  recoveryFailed,
}

/// Immutable snapshot of the authentication state.
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.accessToken,
    this.userId,
    this.email,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? accessToken;
  final String? userId;
  final String? email;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    String? accessToken,
    String? userId,
    String? email,
    String? errorMessage,
    bool clearToken = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      accessToken: clearToken ? null : (accessToken ?? this.accessToken),
      userId: clearToken ? null : (userId ?? this.userId),
      email: clearToken ? null : (email ?? this.email),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
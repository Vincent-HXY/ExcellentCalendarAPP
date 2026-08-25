import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../data/user/user_profile_file_cache.dart';
import '../../native_contract/user/current_user_response_dto.dart';
import '../auth/auth_messages.dart';
import '../auth/auth_service.dart';
import '../auth/auth_session_controller.dart';

enum ProfileLoadPhase { loading, ready, stale, error }

enum ProfileActionOutcome { deletedAvatar, failed }

/// Presentation projection of the user aggregate. Keeps contract DTOs out of
/// the Presentation layer.
class ProfileViewData {
  const ProfileViewData({
    required this.displayName,
    required this.username,
    required this.email,
    required this.isEmailVerified,
    required this.locale,
    required this.timezone,
    required this.avatarThumbnailUrl,
  });

  final String displayName;
  final String username;
  final String email;
  final bool isEmailVerified;
  final String locale;
  final String timezone;
  final String? avatarThumbnailUrl;

  bool get hasAvatar => avatarThumbnailUrl != null;
}

/// Loads the profile with cache-first display: cached data renders instantly
/// while user.get_current refreshes it.
class ProfileController extends ChangeNotifier {
  ProfileController({
    required AuthService authService,
    required AuthSessionController session,
    required UserProfileCacheStore profileCache,
  }) : _authService = authService,
       _session = session,
       _profileCache = profileCache;

  final AuthService _authService;
  final AuthSessionController _session;
  final UserProfileCacheStore _profileCache;

  ProfileLoadPhase _phase = ProfileLoadPhase.loading;
  String? _errorMessage;
  bool _deletingAvatar = false;
  String? _actionError;
  bool _disposed = false;

  ProfileLoadPhase get phase => _phase;
  CurrentUserResponseDto? get user => _session.currentUser;
  String? get errorMessage => _errorMessage;
  bool get isDeletingAvatar => _deletingAvatar;
  String? get actionError => _actionError;

  /// Presentation projection; null while the user is not loaded yet.
  ProfileViewData? get viewData {
    final user = _session.currentUser;
    if (user == null) {
      return null;
    }
    return ProfileViewData(
      displayName: user.profile.displayName,
      username: user.profile.username,
      email: user.account.email,
      isEmailVerified: user.account.isEmailVerified,
      locale: user.preferences.locale,
      timezone: user.preferences.timezone,
      avatarThumbnailUrl: user.profile.avatar?.thumbnailUrl,
    );
  }

  /// Cache-first: shows memory/cache user immediately, then refreshes.
  Future<void> load() async {
    _phase = ProfileLoadPhase.loading;
    _errorMessage = null;
    _notify();
    final memoryUser = _session.currentUser;
    if (memoryUser == null) {
      final cached = await _profileCache.read();
      if (cached != null) {
        _session.updateCurrentUser(cached.currentUser);
        _phase = ProfileLoadPhase.stale;
        _notify();
      }
    }
    try {
      await _authService.refreshCurrentUser();
      _phase = ProfileLoadPhase.ready;
      _errorMessage = null;
    } on BackendApiException catch (error) {
      _errorMessage = backendErrorMessage(error.code);
      _markLoadedOrError();
    } on BackendTransportException catch (error) {
      _errorMessage = transportErrorMessage(error);
      _markLoadedOrError();
    } on BackendContractException {
      _errorMessage = contractErrorMessage();
      _markLoadedOrError();
    } on SessionEndedException {
      _errorMessage = '登录状态已失效，请重新登录';
      _markLoadedOrError();
    }
    _notify();
  }

  void _markLoadedOrError() {
    _phase = _session.currentUser == null
        ? ProfileLoadPhase.error
        : ProfileLoadPhase.stale;
  }

  Future<ProfileActionOutcome> deleteAvatar() async {
    if (_deletingAvatar) {
      return ProfileActionOutcome.failed;
    }
    _deletingAvatar = true;
    _actionError = null;
    _notify();
    try {
      final updated = await _authService.userGateway.deleteAvatar();
      _session.updateCurrentUser(updated);
      await _authService.refreshCurrentUser();
      return ProfileActionOutcome.deletedAvatar;
    } on BackendApiException catch (error) {
      _actionError = backendErrorMessage(error.code);
      return ProfileActionOutcome.failed;
    } on BackendTransportException catch (error) {
      _actionError = transportErrorMessage(error);
      return ProfileActionOutcome.failed;
    } on BackendContractException {
      _actionError = contractErrorMessage();
      return ProfileActionOutcome.failed;
    } finally {
      _deletingAvatar = false;
      _notify();
    }
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

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../auth/logout_service.dart';

enum AccountSecurityPhase { idle, working }

enum AccountSecurityOutcome { loggedOut, failed }

/// Drives logout and logout-all with double confirmation delegated to the
/// page; local cleanup always completes.
class AccountSecurityController extends ChangeNotifier {
  AccountSecurityController(this._logoutService);

  final LogoutService _logoutService;

  AccountSecurityPhase _phase = AccountSecurityPhase.idle;
  String? _errorMessage;
  bool _disposed = false;

  AccountSecurityPhase get phase => _phase;
  bool get isWorking => _phase == AccountSecurityPhase.working;
  String? get errorMessage => _errorMessage;

  Future<AccountSecurityOutcome> logout() => _run(_logoutService.logout);

  Future<AccountSecurityOutcome> logoutAll() => _run(_logoutService.logoutAll);

  Future<AccountSecurityOutcome> _run(Future<void> Function() operation) async {
    if (isWorking) {
      return AccountSecurityOutcome.failed;
    }
    _phase = AccountSecurityPhase.working;
    _errorMessage = null;
    _notify();
    try {
      await operation();
      return AccountSecurityOutcome.loggedOut;
    } catch (_) {
      // Local cleanup is guaranteed by LogoutService; treat as logged out
      // only when cleanup itself failed is surfaced as error.
      _errorMessage = '退出时遇到问题，本地登录状态已清除';
      return AccountSecurityOutcome.failed;
    } finally {
      _phase = AccountSecurityPhase.idle;
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
